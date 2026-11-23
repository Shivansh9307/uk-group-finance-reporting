<#
.SYNOPSIS
Runs every DAX test file against the model open in Power BI Desktop and writes a normalised result CSV for each.

.DESCRIPTION
Calls tools\run_dax.ps1 (it finds the Desktop engine and writes the CSVs), then rewrites each result file so that it is
deterministic and holds nothing from this machine: no byte-order mark, LF line ends, and column names stripped to the
bare name (dscmd writes [name] or Table[name]). The values are not changed; `ukfr dax-compare` reads numbers as text
and compares them with a tolerance.

The results land in tests\results. Compare them with the expected values (`ukfr expected`) using `ukfr dax-compare`.

Run with Windows PowerShell 5.1 (powershell.exe), as run_dax.ps1 does.

.PARAMETER Filter
File name filter inside tests\dax. Default *.dax.

.PARAMETER Refresh
Request a full data refresh first (passed to run_dax.ps1).

.PARAMETER RefreshTable
Refresh only these tables first (comma-separated names, passed to run_dax.ps1).

.PARAMETER AllowUnloaded
Tables that may be unloaded (comma-separated, passed to run_dax.ps1).

.PARAMETER WindowTitle
Desktop window title pattern (passed to run_dax.ps1). Default UKGroupFinance*.

.PARAMETER QueryDir
Folder of query files, relative to the repository root. Default tests\dax. The model reference uses tools\model_reference.

.PARAMETER OutDir
Folder for the normalised result files, relative to the repository root. Default tests\results. The model reference
uses evidence\model\reference.

.EXAMPLE
powershell.exe -NoProfile -File tools\run_dax_tests.ps1 -QueryDir tools\model_reference -OutDir evidence\model\reference

.EXAMPLE
powershell.exe -NoProfile -File tools\run_dax_tests.ps1

.EXAMPLE
powershell.exe -NoProfile -File tools\run_dax_tests.ps1 -Filter "700_*.dax"
#>
param(
    [string]$Filter = "*.dax",
    [switch]$Refresh,
    [string]$RefreshTable = "",
    [string]$AllowUnloaded = "",
    [string]$WindowTitle = "UKGroupFinance*",
    [string]$QueryDir = "tests\dax",
    [string]$OutDir = "tests\results"
)
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSEdition -eq "Core") { throw "Run this script with Windows PowerShell 5.1 (powershell.exe), not pwsh." }

$root = Split-Path -Parent $PSScriptRoot
$queryDir = Join-Path $root $QueryDir
$outDir = Join-Path $root $OutDir
$runner = Join-Path $PSScriptRoot "run_dax.ps1"

$extra = @{}
if ($Refresh) { $extra["Refresh"] = $true }
if ($RefreshTable) { $extra["RefreshTable"] = $RefreshTable }
if ($AllowUnloaded) { $extra["AllowUnloaded"] = $AllowUnloaded }
$status = 0
try {
    & $runner -QueryDir $queryDir -Filter $Filter -OutDir $outDir -WindowTitle $WindowTitle @extra
    if ($LASTEXITCODE -ne 0) { $status = $LASTEXITCODE }
}
catch { throw }

$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($file in (Get-ChildItem $queryDir -Filter $Filter | Sort-Object Name)) {
    $csv = Join-Path $outDir ($file.BaseName + ".csv")
    if (-not (Test-Path $csv)) { continue }
    $text = [System.IO.File]::ReadAllText($csv)
    $text = $text.TrimStart([char]0xFEFF)
    $text = $text -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = $text -split "`n"
    if ($lines.Count -gt 0) {
        # header: one line of comma-separated names, each possibly [name], Table[name] or "[name]"
        $cells = $lines[0] -split ","
        $clean = foreach ($c in $cells) {
            $t = $c.Trim().Trim('"')
            if ($t -match '^(?:.*)?\[(.+)\]$') { $t = $Matches[1] }
            $t
        }
        $lines[0] = ($clean -join ",")
    }
    $text = ($lines -join "`n")
    if (-not $text.EndsWith("`n")) { $text += "`n" }
    [System.IO.File]::WriteAllText($csv, $text, $utf8)
}
if ($status -ne 0) { exit $status }
