<#
.SYNOPSIS
Takes a screenshot of every page of the report open in Power BI Desktop and crops each one to the page canvas.

.DESCRIPTION
`pbir desktop screenshot` captures the Desktop window below its title bar: the page, drawn to fit the space left of the
filter pane, and the filter pane itself. The crop keeps the page and drops the grey margin and the filter pane, so the
image holds the report and nothing of the machine (no account name, no path). The page is drawn at a fixed fraction of
its 1280 x 720 size in the capture, which is found from the width left of the filter pane; the rectangle was read off
a capture at scale 2 and is checked here by looking for the page's own background colour at its corners.

Run from the repository root, with the report open in Desktop and its data refreshed, using Windows PowerShell 5.1:

  powershell.exe -NoProfile -File tools\crop_screenshots.ps1

Output: screenshots\<nn>_<page>.png (cropped). The raw captures go to a scratch folder and are deleted.

.PARAMETER Pages
Display names of the pages, in order. Default: the ten pages of the report.

.PARAMETER StartIndex
Number of the first page in the file names. Default 1; 8 captures only the three NHS pages (-Pages and -Slugs then name those three).

.PARAMETER Wait
Seconds to wait after the first page is requested, so that visuals have drawn. Default 20.
#>
param(
    [string[]] $Pages = @('Executive summary', 'P&L statement', 'Variance', 'Restatements', 'Data controls', 'Department detail', 'Group detail', 'NHS balance sheet', 'NHS cash flow', 'NHS elimination control'),
    [string[]] $Slugs = @('executive_summary', 'pnl_statement', 'variance', 'restatements', 'data_controls', 'department_detail', 'group_detail', 'nhs_balance_sheet', 'nhs_cash_flow', 'nhs_elimination_control'),
    [int] $StartIndex = 1,
    [int] $Wait = 20,
    [string] $Report = 'UKGroupFinance.Report',
    [int] $Scale = 2,
    [int] $X = 0,
    [int] $Y = 180,
    [int] $Width = 2034,
    [int] $Height = 1144
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repo = Split-Path -Parent $PSScriptRoot
$out = Join-Path $repo 'screenshots'
New-Item -ItemType Directory -Force $out | Out-Null
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('ukfr_shots_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $scratch | Out-Null
Push-Location (Join-Path $repo 'model')
try {
    Start-Sleep -Seconds $Wait
    for ($i = 0; $i -lt $Pages.Count; $i++) {
        $raw = Join-Path $scratch ("raw_{0}.png" -f $i)
        & pbir desktop screenshot "$Report/$($Pages[$i]).Page" -o $raw --scale $Scale | Out-Null
        if (-not (Test-Path $raw)) { throw "no capture for $($Pages[$i])" }
        $src = [System.Drawing.Bitmap]::FromFile($raw)
        try {
            if ($src.Width -lt ($X + $Width) -or $src.Height -lt ($Y + $Height)) { throw "capture is $($src.Width) x $($src.Height), smaller than the crop" }
            $rect = New-Object System.Drawing.Rectangle $X, $Y, $Width, $Height
            $dst = $src.Clone($rect, $src.PixelFormat)
            $name = ('{0:D2}_{1}.png' -f ($i + $StartIndex), $Slugs[$i])
            $dst.Save((Join-Path $out $name), [System.Drawing.Imaging.ImageFormat]::Png)
            $dst.Dispose()
            Write-Host ("wrote screenshots\{0} ({1} x {2})" -f $name, $Width, $Height)
        }
        finally { $src.Dispose() }
    }
}
finally {
    Pop-Location
    Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
}
