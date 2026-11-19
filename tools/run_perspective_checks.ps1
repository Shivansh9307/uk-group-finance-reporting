<#
.SYNOPSIS
Runs the queries of tests\perspectives under a perspective (Cube=<name> on the connection) and writes what the engine did.

.DESCRIPTION
A perspective narrows the metadata a client sees; it does not stop a query. This runs four queries under the Executive
perspective (one that uses an object inside it, three that name an object outside it) and one under a perspective that
does not exist, and records for each whether the engine answered, and the value or the error text, in
evidence\model\perspective_queries.csv. Run it with Power BI Desktop open on model\UKGroupFinance.pbip and the data
refreshed (tools\run_dax.ps1 -Refresh). Windows PowerShell 5.1.

.PARAMETER WindowTitle
Desktop window title pattern (passed to run_dax.ps1). Default UKGroupFinance*.

.EXAMPLE
powershell.exe -NoProfile -File tools\run_perspective_checks.ps1
#>
param([string]$WindowTitle = "UKGroupFinance*")
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSEdition -eq "Core") { throw "Run this script with Windows PowerShell 5.1 (powershell.exe), not pwsh." }

$root = Split-Path -Parent $PSScriptRoot
$queryDir = Join-Path $root "tests\perspectives"
$runner = Join-Path $PSScriptRoot "run_dax.ps1"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("perspective_checks_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $tmp | Out-Null

$cases = @(
    @{ File = "in_measure.dax";  Perspective = "Executive";         Inside = "yes" },
    @{ File = "out_measure.dax"; Perspective = "Executive";         Inside = "no" },
    @{ File = "out_column.dax";  Perspective = "Executive";         Inside = "no" },
    @{ File = "out_table.dax";   Perspective = "Executive";         Inside = "no" },
    @{ File = "in_measure.dax";  Perspective = "NoSuchPerspective"; Inside = "no such perspective" }
)
$lines = @("query,perspective,object_in_perspective,engine_answered,result")
try {
    foreach ($c in $cases) {
        $out = Join-Path $tmp ([guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force $out | Out-Null
        $text = (& $runner -QueryDir $queryDir -Filter $c.File -OutDir $out -Perspective $c.Perspective -WindowTitle $WindowTitle *>&1 | Out-String)
        $csv = Get-ChildItem $out -Filter *.csv -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($csv -and ($text -match "(?m)^ok\s")) {
            $value = (Get-Content $csv.FullName | Select-Object -Skip 1 -First 1).Trim()
            $lines += ('{0},{1},{2},yes,{3}' -f $c.File, $c.Perspective, $c.Inside, $value)
        } else {
            $err = ($text -split "`n" | Where-Object { $_ -match "Error:" } | Select-Object -First 1)
            $err = ("$err" -replace '^\s*\d\d:\d\d:\d\d \[ERR\] Error:\s*', '').Trim()
            $lines += ('{0},{1},{2},no,"{3}"' -f $c.File, $c.Perspective, $c.Inside, $err.Replace('"', "'"))
        }
    }
}
finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }

$dest = Join-Path $root "evidence\model\perspective_queries.csv"
[IO.File]::WriteAllText($dest, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
$lines | ForEach-Object { Write-Host $_ }
