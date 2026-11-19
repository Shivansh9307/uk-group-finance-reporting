<#
.SYNOPSIS
  Runs the Tabular Editor 2 Best Practice Analyzer on a TMDL folder and fails only on
  violations at or above a severity threshold.

.DESCRIPTION
  TE2 on its own exits 1 when any rule of severity 3 or more is violated, prints severity 2
  as a warning and severity 1 as plain text. This wrapper keeps TE2's console output (with
  -G, so GitHub shows annotations), reads the per-rule results from the TRX file TE2 writes
  with -T, and decides the exit code itself from -FailAtSeverity.

.EXAMPLE
  ./run-bpa.ps1 -TabularEditor TabularEditor.exe -Model model/definition -Rules bpa-rules.json -FailAtSeverity 3
#>
param(
    [Parameter(Mandatory)] [string] $TabularEditor,
    [Parameter(Mandatory)] [string] $Model,
    [Parameter(Mandatory)] [string] $Rules,
    [int] $FailAtSeverity = 3,
    [string] $TrxPath = (Join-Path ([IO.Path]::GetTempPath()) 'bpa-results.trx')
)

$ErrorActionPreference = 'Stop'
# Resolve to full paths; TE2 is a .NET Framework app and is safest with absolute paths.
$Model = (Resolve-Path $Model).Path.TrimEnd('\', '/')
$Rules = (Resolve-Path $Rules).Path

# -A <rules>: analyse with this rule file only (plus rules embedded in model annotations).
# -G: emit ::warning:: / ::error:: workflow commands. -T: write a TRX file with per-rule results.
& $TabularEditor $Model -A $Rules -G -T $TrxPath | Tee-Object -Variable teOutput | Out-Host
$teExit = $LASTEXITCODE
Write-Host "TabularEditor exit code: $teExit"
# A rule whose expression does not parse is reported on the console as 'Error on rule' and is not a violation.
if (($teOutput | Out-String) -match 'Error on rule') { throw 'TE2 could not evaluate at least one rule (see the lines starting Error on rule above).' }
if (-not (Test-Path $TrxPath)) { throw "TE2 did not write $TrxPath; the model probably failed to load." }

[xml] $trx = Get-Content -Raw -Encoding utf8 $TrxPath
$ns = @{ t = 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010' }
$severity = @{}
foreach ($def in (Select-Xml -Xml $trx -XPath '//t:UnitTest' -Namespace $ns)) {
    $sev = ($def.Node.Properties.Property | Where-Object Key -eq 'Severity').Value
    $severity[$def.Node.id] = [int] $sev
}
$failed = foreach ($res in (Select-Xml -Xml $trx -XPath "//t:UnitTestResult[@outcome='Failed']" -Namespace $ns)) {
    [pscustomobject] @{
        Rule     = $res.Node.testName -replace '\s+', ' '
        Severity = $severity[$res.Node.testId]
        Detail   = $res.Node.Output.ErrorInfo.Message
    }
}

$blocking = @($failed | Where-Object Severity -ge $FailAtSeverity)
$advisory = @($failed | Where-Object Severity -lt $FailAtSeverity)
Write-Host "Rules violated: $(@($failed).Count) (blocking at severity >= ${FailAtSeverity}: $($blocking.Count), advisory: $($advisory.Count))"
$failed | Sort-Object Severity -Descending | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

if ($env:GITHUB_STEP_SUMMARY) {
    $lines = @("### Best Practice Analyzer", "", "Fail threshold: severity >= $FailAtSeverity; TE2 exit code $teExit", "",
        "| Severity | Rule | Result |", "|---|---|---|")
    $lines += $failed | Sort-Object Severity -Descending | ForEach-Object {
        $kind = if ($_.Severity -ge $FailAtSeverity) { 'blocking' } else { 'advisory' }
        "| $($_.Severity) | $($_.Rule) | $($_.Detail) ($kind) |"
    }
    $lines | Out-File -Append -Encoding utf8 $env:GITHUB_STEP_SUMMARY
}

if ($blocking.Count -gt 0) { exit 1 }
exit 0
