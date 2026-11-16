<#
.SYNOPSIS
Runs DAX query files against a model open in Power BI Desktop and writes each result to a CSV.

.DESCRIPTION
On this machine `pbir model -q` cannot reach Desktop's local engine (Store install), so the queries go to the
engine port directly with dscmd.exe, the command-line utility that ships with DAX Studio.

The engine is found from the Desktop window: the msmdsrv.exe child process of the PBIDesktop.exe whose window
title matches -WindowTitle. A stand-alone Analysis Services service on the same machine is never picked up,
because it is not a child of Desktop.

Run with Windows PowerShell 5.1, not PowerShell 7: the Tabular Object Model library that reads the database name and
requests a refresh is a .NET Framework build. The DLLs are loaded from the Tabular Editor 2 folder.

-Refresh asks the engine for a full data refresh first. That leaves Desktop with unsaved changes; nothing is
written to the project files. A refresh that fails (for example because no credential is stored for a source yet)
stops the script with the engine's error text.

-Roles and -User run the queries under row-level security. -Roles alone applies the role to your own Windows
identity. -User needs -Roles. The local engine rejects EffectiveUserName, so -User uses the ActAs authentication
scheme, the mechanism Desktop uses for "View as > Other user".

-Perspective adds Cube=<name> to the connection string. The engine checks the name, and metadata (MDSCHEMA
rowsets) is limited to the perspective, but DAX queries can still reach objects outside it: a perspective is not
a security boundary.

Help: powershell.exe -NoProfile -Command "Get-Help .\tools\run_dax.ps1 -Full" (-? after -File prints nothing).

-Benchmark times each query instead of exporting its result (dscmd benchmark, cold and warm cache runs).
-Vpax <file> exports the model's size statistics (VertiPaq Analyzer) and runs no queries. The file holds the full
model definition (including Power Query source expressions, which can contain local paths) and the server name,
so keep it out of the repository and summarise it with tools/vpax_summary.py.

.PARAMETER QueryDir
Folder holding the .dax files. Default tests\dax.

.PARAMETER Filter
File name filter inside -QueryDir. Default *.dax.

.PARAMETER OutDir
Folder for the result CSVs. Default tests\results.

.PARAMETER WindowTitle
Wildcard matched against the Desktop window title (the project name). Default UKGroupFinance*.

.PARAMETER Roles
Comma-separated model roles to apply.

.PARAMETER User
User name to impersonate with ActAs (needs -Roles).

.PARAMETER Perspective
Perspective name, passed as Cube=<name>.

.PARAMETER OutSuffix
Text appended to each output file name, for example _role_a.

.PARAMETER Vpax
Write a .vpax file to this path and exit.

.PARAMETER Benchmark
Run dscmd benchmark (-Cold cold and -Warm warm runs) instead of exporting results.

.PARAMETER Refresh
Request a full data refresh through TOM before running queries.

.PARAMETER DscmdPath
Path to dscmd.exe. Found on PATH or under %LOCALAPPDATA%\Programs\DAX Studio when omitted.

.PARAMETER TomDir
Folder holding Microsoft.AnalysisServices.Tabular.dll. The Tabular Editor 2 folder is used when omitted.

.EXAMPLE
powershell.exe -NoProfile -File tools\run_dax.ps1 -Filter "stage2_*.dax" -Refresh

.EXAMPLE
powershell.exe -NoProfile -File tools\run_dax.ps1 -Filter "rls_*.dax" -Roles "Department Finance" -User "user.a@example.org" -OutSuffix "_user_a"

.EXAMPLE
powershell.exe -NoProfile -File tools\run_dax.ps1 -QueryDir tests\perf -OutDir tests\perf_results -Benchmark
#>
param(
    [string]$QueryDir = "tests\dax",
    [string]$Filter = "*.dax",
    [string]$OutDir = "tests\results",
    [string]$WindowTitle = "UKGroupFinance*",
    [string]$Roles = "",
    [string]$User = "",
    [string]$Perspective = "",
    [string]$OutSuffix = "",
    [string]$Vpax = "",
    [switch]$Benchmark,
    [int]$Cold = 5,
    [int]$Warm = 5,
    [switch]$Refresh,
    [string]$DscmdPath = "",
    [string]$TomDir = ""
)
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSEdition -eq "Core") { throw "Run this script with Windows PowerShell 5.1 (powershell.exe), not pwsh." }

if (-not $DscmdPath) {
    $cmd = Get-Command dscmd.exe -ErrorAction SilentlyContinue
    if ($cmd) { $DscmdPath = $cmd.Source } else { $DscmdPath = Join-Path $env:LOCALAPPDATA "Programs\DAX Studio\dscmd.exe" }
}
if (-not (Test-Path $DscmdPath)) { throw "dscmd.exe not found. Install DAX Studio or pass -DscmdPath." }

if (-not $TomDir) {
    $te = Get-Command TabularEditor.exe -ErrorAction SilentlyContinue
    if ($te) { $TomDir = Split-Path $te.Source }
    else {
        $dll = Get-ChildItem (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages") -Filter "Microsoft.AnalysisServices.Tabular.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dll) { $TomDir = $dll.DirectoryName }
    }
}
if (-not $TomDir -or -not (Test-Path (Join-Path $TomDir "Microsoft.AnalysisServices.Tabular.dll"))) {
    throw "Microsoft.AnalysisServices.Tabular.dll not found. Pass -TomDir with the Tabular Editor 2 folder."
}

$desktops = @(Get-Process PBIDesktop -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like $WindowTitle })
if ($desktops.Count -eq 0) { throw "No Power BI Desktop window with a title like '$WindowTitle' is open." }
if ($desktops.Count -gt 1) { throw "$($desktops.Count) Desktop windows match '$WindowTitle'. Pass a more specific -WindowTitle." }
$desktop = $desktops[0]
$engine = Get-CimInstance Win32_Process -Filter "Name='msmdsrv.exe'" | Where-Object { $_.ParentProcessId -eq $desktop.Id } | Select-Object -First 1
if (-not $engine) { throw "Desktop (PID $($desktop.Id)) has no Analysis Services engine yet. Wait for the model to load." }
$port = Get-NetTCPConnection -OwningProcess $engine.ProcessId -State Listen | Select-Object -ExpandProperty LocalPort -Unique | Select-Object -First 1
if (-not $port) { throw "Could not find the listening port of the engine (PID $($engine.ProcessId))." }
$server = "localhost:$port"

Add-Type -Path (Join-Path $TomDir "Microsoft.AnalysisServices.Core.dll")
Add-Type -Path (Join-Path $TomDir "Microsoft.AnalysisServices.Tabular.dll")
$tom = New-Object Microsoft.AnalysisServices.Tabular.Server
$tom.Connect($server)
try {
    if ($tom.Databases.Count -ne 1) { throw "Expected one database on $server, found $($tom.Databases.Count)." }
    $db = $tom.Databases[0]
    $database = $db.Name
    if ($Refresh) {
        Write-Host "Requesting a full refresh on $server ..."
        $started = Get-Date
        # Desktop's engine cannot apply an incremental refresh policy: a refresh that tries to (TOM RequestRefresh, or
        # TMSL without the flag) fails with "An unexpected exception occurred". applyRefreshPolicy=false refreshes the
        # table's own partition instead.
        $tmsl = '{"refresh":{"type":"full","applyRefreshPolicy":false,"objects":[{"database":"' + $database.Replace('"', '\"') + '"}]}}'
        $result = $tom.Execute($tmsl)
        $messages = @($result | ForEach-Object { $_.Messages } | ForEach-Object { $_.Description })
        if ($messages.Count -gt 0) { throw "Refresh failed:`n$($messages -join "`n")" }
        Write-Host ("Refresh finished in {0:N1} s" -f ((Get-Date) - $started).TotalSeconds)
        $db.Refresh()
    }
    $notReady = @($db.Model.Tables | ForEach-Object { $_.Partitions } | Where-Object { $_.State -ne "Ready" })
    if ($notReady.Count -gt 0) {
        $names = ($notReady | ForEach-Object { "$($_.Table.Name)/$($_.Name)=$($_.State)" }) -join ", "
        throw "$($notReady.Count) partition(s) are not loaded ($names). Refresh in Desktop or rerun with -Refresh."
    }
}
finally { $tom.Disconnect() }

if ($Vpax) {
    & $DscmdPath vpax $Vpax -s $server -d $database 2>&1 | ForEach-Object { Write-Host $_ }
    if (-not (Test-Path $Vpax)) { exit 1 }
    exit 0
}
if ($User -and -not $Roles) { throw "-User needs -Roles: without a role no security filter applies." }
$connection = "Data Source=$server;Initial Catalog=$database"
if ($Perspective) { $connection += ";Cube=$Perspective" }
if ($Roles) { $connection += ";Roles=$Roles" }
if ($User) {
    $connection += ";Authentication Scheme=ActAs;Ext Auth Info=`"<Properties><UserName>$User</UserName><BypassAuthorization>true</BypassAuthorization><RestrictCatalog>$database</RestrictCatalog></Properties>`""
}
# Windows PowerShell passes embedded double quotes to native programs unescaped, so escape them here.
$connectionArg = $connection.Replace('"', '\"')

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$files = @(Get-ChildItem $QueryDir -Filter $Filter | Sort-Object Name)
if ($files.Count -eq 0) { throw "No query files match $QueryDir\$Filter." }
$label = ""
if ($Roles) { $label += " as [$Roles] $User" }
if ($Perspective) { $label += " in perspective [$Perspective]" }
$failed = 0
foreach ($file in $files) {
    $out = Join-Path $OutDir ($file.BaseName + $OutSuffix + ".csv")
    if (Test-Path $out) { Remove-Item $out -Confirm:$false }
    if ($Benchmark) { $log = & $DscmdPath benchmark $out -c $connectionArg -f $file.FullName --cold $Cold --warm $Warm 2>&1 }
    else { $log = & $DscmdPath csv $out -c $connectionArg -f $file.FullName 2>&1 }
    if (Test-Path $out) { Write-Host "ok      $($file.Name)$label -> $out" }
    else { $failed++; Write-Host "FAILED  $($file.Name)$label"; $log | ForEach-Object { Write-Host "        $_" } }
}
if ($failed -gt 0) { exit 1 }
