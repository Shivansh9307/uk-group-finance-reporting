<#
.SYNOPSIS
Runs one MDX query against the model open in Power BI Desktop and writes every cell with its value and the value as
the engine formats it.

.DESCRIPTION
DAX cannot return the dynamic format string that the engine applies to a cell. MDX can return the result of it, through
the cell property FORMATTED_VALUE, so this is how a calculation item's format string expression is proved to be the
one in force. (The FORMAT_STRING property itself comes back empty for these cells, so it is not written.) The engine is found the same way as in tools/run_dax.ps1 (the msmdsrv.exe child of the PBIDesktop.exe
whose window title matches -WindowTitle) and the query runs over ADOMD.NET.

The output has one row per cell: the member captions of the rows (joined with " | "), the column caption, the value
and the formatted value. Pound signs are written as GBP so that the file does not depend on a
code page. Scaled number formats (commas after the digits) are not used in this model; do not rely on FORMATTED_VALUE
for them, check them on the canvas (docs/spikes/desktop_capabilities.md).

Run with Windows PowerShell 5.1 (powershell.exe), as the other tools do.

.PARAMETER MdxFile
The MDX query. It should select CELL PROPERTIES VALUE, FORMATTED_VALUE.

.PARAMETER OutFile
The CSV to write.

.PARAMETER WindowTitle
Wildcard matched against the Desktop window title. Default UKGroupFinance*.

.PARAMETER AdomdPath
Path to Microsoft.AnalysisServices.AdomdClient.dll. Found next to DAX Studio when omitted.

.EXAMPLE
powershell.exe -NoProfile -File tools\run_mdx.ps1 -MdxFile tests\mdx\format_strings.mdx -OutFile evidence\model\format_strings.csv
#>
param(
    [Parameter(Mandatory)] [string]$MdxFile,
    [Parameter(Mandatory)] [string]$OutFile,
    [string]$WindowTitle = "UKGroupFinance*",
    [string]$AdomdPath = ""
)
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSEdition -eq "Core") { throw "Run this script with Windows PowerShell 5.1 (powershell.exe), not pwsh." }

if (-not $AdomdPath) {
    $candidates = @()
    $ds = Get-Command dscmd.exe -ErrorAction SilentlyContinue
    if ($ds) { $candidates += Join-Path (Split-Path $ds.Source) "bin\Microsoft.AnalysisServices.AdomdClient.dll" }
    $candidates += Join-Path $env:LOCALAPPDATA "Programs\DAX Studio\bin\Microsoft.AnalysisServices.AdomdClient.dll"
    $AdomdPath = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $AdomdPath) { throw "Microsoft.AnalysisServices.AdomdClient.dll not found. Pass -AdomdPath." }

$desktops = @(Get-Process PBIDesktop -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like $WindowTitle })
if ($desktops.Count -eq 0) { throw "No Power BI Desktop window with a title like '$WindowTitle' is open." }
if ($desktops.Count -gt 1) { throw "$($desktops.Count) Desktop windows match '$WindowTitle'. Pass a more specific -WindowTitle." }
$engine = Get-CimInstance Win32_Process -Filter "Name='msmdsrv.exe'" | Where-Object { $_.ParentProcessId -eq $desktops[0].Id } | Select-Object -First 1
if (-not $engine) { throw "Desktop has no Analysis Services engine yet. Wait for the model to load." }
$port = Get-NetTCPConnection -OwningProcess $engine.ProcessId -State Listen | Select-Object -ExpandProperty LocalPort -Unique | Select-Object -First 1
if (-not $port) { throw "Could not find the listening port of the engine." }

try { Add-Type -Path $AdomdPath } catch [System.Reflection.ReflectionTypeLoadException] { }
$mdx = [System.IO.File]::ReadAllText((Resolve-Path $MdxFile).Path, [System.Text.Encoding]::UTF8)
$conn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection("Data Source=localhost:$port")
$conn.Open()
try {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $mdx
    $cs = $cmd.ExecuteCellSet()
    $rows = New-Object System.Collections.Generic.List[object]
    $nCols = $cs.Axes[0].Positions.Count
    $nRows = if ($cs.Axes.Count -gt 1) { $cs.Axes[1].Positions.Count } else { 1 }
    for ($r = 0; $r -lt $nRows; $r++) {
        $label = ""
        if ($cs.Axes.Count -gt 1) {
            $label = ($cs.Axes[1].Positions[$r].Members | ForEach-Object { $_.Caption }) -join " | "
        }
        for ($c = 0; $c -lt $nCols; $c++) {
            $colLabel = ($cs.Axes[0].Positions[$c].Members | ForEach-Object { $_.Caption }) -join " | "
            if ($cs.Axes.Count -gt 1) { $cell = $cs.Cells[$c, $r] } else { $cell = $cs.Cells[$c] }
            $rows.Add([pscustomobject]@{
                row            = ($label -replace [char]163, "GBP ")
                column         = $colLabel
                value          = if ($null -eq $cell.Value) { "" } else { [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0}", $cell.Value) }
                formatted      = ([string]$cell.FormattedValue -replace [char]163, "GBP ")
            })
        }
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $csv = ($rows | ConvertTo-Csv -NoTypeInformation) -join "`n"
    [System.IO.File]::WriteAllText($OutFile, $csv + "`n", $utf8)
    Write-Host "wrote $($rows.Count) cells to $OutFile"
}
finally { $conn.Close() }
