<#
.SYNOPSIS
Runs the row-level and object-level security cases of tests\rls\manifest.csv against the model open in Power BI Desktop.

.DESCRIPTION
Each row of the manifest names a DAX query (tests\rls\queries\<query>.dax), a role and an invented user. The query is
run through tools\run_dax.ps1 with -Roles and -User, which uses the ActAs scheme: the user name is what
USERPRINCIPALNAME() returns inside the role. Without -User the name would be MACHINE\user on this machine and match no
row, so every case passes a user.

The result of a case is written to tests\rls\results\<query>__<case>.csv:
- a query that answers is written as the engine returned it, with no byte-order mark, LF line ends and bare column
  names (the same normalisation as tools\run_dax_tests.ps1);
- a query that the engine refuses (object-level security, or any other error) is written as `outcome,message` with one
  row, `error` and the engine's message, with the port number and any path or machine name taken out.

Compare the results with the expected values from the warehouse:

    uv run --project pipeline ukfr rls-expected
    uv run --project pipeline ukfr rls-compare

-ProbeMeasures does not run the manifest. It evaluates every measure of the model once, alone, as the role and user
given (default Restricted Viewer and chloe.patel@example.org), and writes evidence\model\ols_measure_probe.csv with
`ok` or `error` and the message for each. A measure that reads an object hidden by object-level security errors; one
that does not, answers (possibly with a blank). Run with Windows PowerShell 5.1, as run_dax.ps1 does.

.PARAMETER Filter
Wildcard on the result stem of a case (`<query>__<case>`). Default all cases.

.PARAMETER Refresh
Ask the engine for a full data refresh before the first case (passed to run_dax.ps1).

.PARAMETER WindowTitle
Desktop window title pattern. Default UKGroupFinance*.

.PARAMETER ProbeMeasures
Evaluate every measure alone under -ProbeRole and -ProbeUser and write evidence\model\ols_measure_probe.csv.

.EXAMPLE
powershell.exe -NoProfile -File tools\run_rls_tests.ps1 -Refresh

.EXAMPLE
powershell.exe -NoProfile -File tools\run_rls_tests.ps1 -Filter "totals__*"
#>
param(
    [string]$Filter = "*",
    [switch]$Refresh,
    [string]$WindowTitle = "UKGroupFinance*",
    [switch]$ProbeMeasures,
    [string]$ProbeRole = "Restricted Viewer",
    [string]$ProbeUser = "chloe.patel@example.org"
)
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSEdition -eq "Core") { throw "Run this script with Windows PowerShell 5.1 (powershell.exe), not pwsh." }

$root = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $PSScriptRoot "run_dax.ps1"
$queryDir = Join-Path $root "tests\rls\queries"
$outDir = Join-Path $root "tests\rls\results"
$utf8 = New-Object System.Text.UTF8Encoding($false)

function ConvertTo-CleanMessage([string[]]$lines) {
    # one line of text; the engine's port, any local path and any machine or account name are taken out
    # keep dscmd's log from the first error line on (the tool wraps a long message onto the lines after it) and drop the
    # time stamp and level: "21:13:47 [ERR] Error: ..." -> "Error: ..."
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match "\[ERR\]") { $start = $i; break } }
    if ($start -ge 0) { $lines = @($lines[$start..($lines.Count - 1)]) }
    $text = ($lines | Where-Object { $_ -and $_.Trim() } | ForEach-Object { ($_.Trim() -replace "^\d{1,2}:\d{2}:\d{2}\s+\[ERR\]\s*", "") }) -join " "
    $text = $text -replace "localhost:\d+", "localhost:<port>"
    $text = $text -replace "[A-Za-z]:\\[^\s'`"]*", "<path>"
    $text = $text.Replace($env:COMPUTERNAME, "<machine>").Replace($env:USERNAME, "<user>")
    $text = $text -replace "\s+", " "
    return $text.Trim()
}

function Write-ErrorResult([string]$path, [string[]]$lines) {
    $message = (ConvertTo-CleanMessage $lines).Replace('"', '""')
    [System.IO.File]::WriteAllText($path, "outcome,message`n" + 'error,"' + $message + '"' + "`n", $utf8)
}

function ConvertTo-CleanResult([string]$path) {
    # no byte-order mark, LF line ends, bare column names (dscmd writes [name] or Table[name])
    $text = [System.IO.File]::ReadAllText($path).TrimStart([char]0xFEFF)
    $text = $text -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = $text -split "`n"
    if ($lines.Count -gt 0) {
        $clean = foreach ($c in ($lines[0] -split ",")) {
            $t = $c.Trim().Trim('"')
            if ($t -match '^(?:.*)?\[(.+)\]$') { $t = $Matches[1] }
            $t
        }
        $lines[0] = ($clean -join ",")
    }
    $text = ($lines -join "`n")
    if (-not $text.EndsWith("`n")) { $text += "`n" }
    [System.IO.File]::WriteAllText($path, $text, $utf8)
}

function Invoke-OneQuery([string]$queryFile, [string]$role, [string]$user, [string]$outFolder, [string]$suffix, [bool]$refreshFirst) {
    # returns the captured console output; the result file exists when the engine answered
    $extra = @{}
    if ($refreshFirst) { $extra["Refresh"] = $true }
    $global:LASTEXITCODE = 0
    $log = & $runner -QueryDir (Split-Path $queryFile) -Filter (Split-Path $queryFile -Leaf) -OutDir $outFolder -WindowTitle $WindowTitle -Roles $role -User $user -OutSuffix $suffix @extra *>&1 | ForEach-Object { "$_" }
    return $log
}

if ($ProbeMeasures) {
    $tables = Join-Path $root "model\UKGroupFinance.SemanticModel\definition\tables"
    $measures = New-Object System.Collections.Generic.List[object]
    foreach ($file in (Get-ChildItem $tables -Filter "*.tmdl" | Sort-Object Name)) {
        foreach ($line in [System.IO.File]::ReadAllLines($file.FullName)) {
            if ($line -match "^\tmeasure (?:'((?:[^']|'')+)'|([^\s=]+))\s*=") {
                $name = if ($Matches[1]) { $Matches[1].Replace("''", "'") } else { $Matches[2] }
                $measures.Add([pscustomobject]@{ Table = [System.IO.Path]::GetFileNameWithoutExtension($file.Name); Measure = $name })
            }
        }
    }
    $scratch = Join-Path $env:TEMP "t21_probe"
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    Get-ChildItem $scratch -File | Remove-Item -Force
    $rows = @("role,user,table,measure,outcome,message")
    $first = [bool]$Refresh
    $i = 0
    foreach ($m in ($measures | Sort-Object Table, Measure)) {
        $i++
        $q = Join-Path $scratch "probe.dax"
        $dax = "EVALUATE ROW(""v"", [" + $m.Measure.Replace("]", "]]") + "])"
        [System.IO.File]::WriteAllText($q, $dax, $utf8)
        $out = Join-Path $scratch "out"
        New-Item -ItemType Directory -Force -Path $out | Out-Null
        Get-ChildItem $out -File | Remove-Item -Force
        $log = Invoke-OneQuery $q $ProbeRole $ProbeUser $out "" $first
        $first = $false
        $result = Join-Path $out "probe.csv"
        if (Test-Path $result) { $outcome = "ok"; $message = "" }
        else {
            $outcome = "error"
            $message = ConvertTo-CleanMessage ($log | Where-Object { $_ -notmatch "^FAILED" -and $_ -notmatch "^Requesting" -and $_ -notmatch "^Refresh finished" })
        }
        $rows += ('"{0}","{1}","{2}","{3}",{4},"{5}"' -f $ProbeRole, $ProbeUser, $m.Table.Replace('"', '""'), $m.Measure.Replace('"', '""'), $outcome, $message.Replace('"', '""'))
        Write-Host ("{0,3}/{1} {2,-5} {3}" -f $i, $measures.Count, $outcome, $m.Measure)
    }
    $evidence = Join-Path $root "evidence\model\ols_measure_probe.csv"
    [System.IO.File]::WriteAllText($evidence, (($rows -join "`n") + "`n"), $utf8)
    $bad = @($rows | Select-Object -Skip 1 | Where-Object { $_ -match ',error,' }).Count
    Write-Host "$($measures.Count) measures evaluated as [$ProbeRole] $ProbeUser; $bad returned an error. Written to evidence\model\ols_measure_probe.csv"
    exit 0
}

$cases = @(Import-Csv (Join-Path $root "tests\rls\manifest.csv") | Where-Object { ($_.query + "__" + $_.case) -like $Filter })
if ($cases.Count -eq 0) { throw "No case matches '$Filter'." }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$failedToRun = 0
$first = [bool]$Refresh
foreach ($c in $cases) {
    $stem = $c.query + "__" + $c.case
    $result = Join-Path $outDir ($stem + ".csv")
    if (Test-Path $result) { Remove-Item $result -Confirm:$false }
    $log = Invoke-OneQuery (Join-Path $queryDir ($c.query + ".dax")) $c.role $c.user $outDir ("__" + $c.case) $first
    $first = $false
    if (Test-Path $result) {
        ConvertTo-CleanResult $result
        Write-Host "ok      $stem as [$($c.role)] $($c.user)"
    }
    else {
        Write-ErrorResult $result ($log | Where-Object { $_ -notmatch "^FAILED" })
        if ($c.mode -eq "error") { Write-Host "refused $stem as [$($c.role)] $($c.user)" }
        else { $failedToRun++; Write-Host "REFUSED $stem as [$($c.role)] $($c.user) (the case expects an answer)" }
    }
}
Write-Host "$($cases.Count) case(s) run. Compare with: uv run --project pipeline ukfr rls-compare"
if ($failedToRun -gt 0) { exit 1 }
