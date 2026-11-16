<#
.SYNOPSIS
    Checks that the local toolchain for this project is installed and reachable.

.DESCRIPTION
    Prints one line per check: ok / MISSING / WARN, with the version or path found.
    Exits 1 if any required item is missing, otherwise 0.
    Runs under Windows PowerShell 5.1 and PowerShell 7.

    Environment variables (optional):
      UKFR_SQL_SERVER    SQL Server instance (default: localhost)
      UKFR_SQL_DATABASE  database name      (default: UKGroupFinance)
#>
$ErrorActionPreference = 'Continue'
Set-StrictMode -Version 2

$script:missing = 0

function Write-Check {
    param([string] $Status, [string] $Name, [string] $Detail)
    if ($Status -eq 'MISSING') { $script:missing++ }
    '{0,-8} {1,-28} {2}' -f $Status, $Name, $Detail
}

function Get-Tool {
    param([string] $Name)
    Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Get-FirstLine {
    param([string] $Exe, [string[]] $ToolArgs)
    try {
        $out = & $Exe @ToolArgs 2>&1 | Where-Object { "$_".Trim() -ne '' } | Select-Object -First 1
        return "$out".Trim()
    } catch { return '' }
}

# Re-read PATH from the registry so tools installed after this shell started are found.
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = (@($env:Path, $machinePath, $userPath) | Where-Object { $_ }) -join ';'

$sqlServer = if ($env:UKFR_SQL_SERVER) { $env:UKFR_SQL_SERVER } else { 'localhost' }
$sqlDatabase = if ($env:UKFR_SQL_DATABASE) { $env:UKFR_SQL_DATABASE } else { 'UKGroupFinance' }
$schemas = @('raw', 'stg', 'dw', 'authored', 'synthetic', 'scale', 'quarantine', 'audit')

"Environment check  (PowerShell $($PSVersionTable.PSVersion), SQL target $sqlServer / $sqlDatabase)"
''

# --- Power BI Desktop (Microsoft Store build) -------------------------------
$pbi = $null
try { $pbi = Get-AppxPackage -Name 'Microsoft.MicrosoftPowerBIDesktop' -ErrorAction Stop | Select-Object -First 1 } catch { $pbi = $null }
if (-not $pbi -and $PSVersionTable.PSEdition -eq 'Core') {
    # Appx module is not always loadable in pwsh; fall back to Windows PowerShell.
    try {
        $v = powershell.exe -NoProfile -Command "(Get-AppxPackage -Name 'Microsoft.MicrosoftPowerBIDesktop' | Select-Object -First 1).Version"
        if ("$v".Trim()) { $pbi = [pscustomobject]@{ Version = "$v".Trim() } }
    } catch { }
}
if ($pbi) { Write-Check 'ok' 'Power BI Desktop' "Appx $($pbi.Version)" }
else { Write-Check 'MISSING' 'Power BI Desktop' 'Appx package Microsoft.MicrosoftPowerBIDesktop not found' }

# --- Executables on PATH -----------------------------------------------------
$te = Get-Tool 'TabularEditor'
if ($te) { Write-Check 'ok' 'Tabular Editor 2' "$((Get-Item $te.Source).VersionInfo.FileVersion)  $($te.Source)" }
else { Write-Check 'MISSING' 'Tabular Editor 2' 'TabularEditor not on PATH' }

$versionArgs = [ordered]@{
    'dscmd' = @('--help')
    'pbir'  = @('--version')
    'uv'    = @('--version')
    'git'   = @('--version')
    'gh'    = @('--version')
}
foreach ($name in $versionArgs.Keys) {
    $t = Get-Tool $name
    if ($t) {
        $line = Get-FirstLine $t.Source $versionArgs[$name]
        Write-Check 'ok' $name "$line  $($t.Source)"
    } else {
        Write-Check 'MISSING' $name 'not on PATH'
    }
}

$sqlcmd = Get-Tool 'sqlcmd'
if ($sqlcmd) { Write-Check 'ok' 'sqlcmd' "$($sqlcmd.Version)  $($sqlcmd.Source)" }
else { Write-Check 'MISSING' 'sqlcmd' 'not on PATH' }

# bcp is optional: loads can go through a Python ODBC client instead.
$bcp = Get-Tool 'bcp'
if ($bcp) {
    Write-Check 'ok' 'bcp' "$((Get-Item $bcp.Source).VersionInfo.ProductVersion)  $($bcp.Source)"
} else { Write-Check 'WARN' 'bcp' 'not on PATH (optional)' }

# --- ODBC driver -------------------------------------------------------------
$odbc = @()
try { $odbc = @(Get-OdbcDriver -Platform '64-bit' -ErrorAction Stop | Where-Object { $_.Name -match '^ODBC Driver \d+ for SQL Server$' } | Select-Object -ExpandProperty Name -Unique) } catch { }
if (-not $odbc) {
    $key = 'HKLM:\SOFTWARE\ODBC\ODBCINST.INI\ODBC Drivers'
    if (Test-Path $key) {
        $odbc = @((Get-Item $key).Property | Where-Object { $_ -match '^ODBC Driver \d+ for SQL Server$' })
    }
}
if ($odbc) { Write-Check 'ok' 'ODBC driver' ($odbc -join ', ') }
else { Write-Check 'MISSING' 'ODBC driver' 'no "ODBC Driver nn for SQL Server" registered' }

# --- SQL Server engine -------------------------------------------------------
function Invoke-Sql {
    param([string] $Query, [switch] $Trust)
    $a = @('-S', $sqlServer, '-E', '-d', $sqlDatabase, '-b', '-h', '-1', '-W', '-l', '10', '-Q', "SET NOCOUNT ON; $Query")
    if ($Trust) { $a = @('-C') + $a }
    $out = & $sqlcmd.Source @a 2>&1
    [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); Lines = @($out | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' }) }
}

if ($sqlcmd) {
    $trust = $false
    $r = Invoke-Sql "SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(50)) + ' ' + CAST(SERVERPROPERTY('Edition') AS nvarchar(100));"
    if (-not $r.Ok -and (($r.Lines -join ' ') -match 'certificate')) {
        $trust = $true
        $r = Invoke-Sql "SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(50)) + ' ' + CAST(SERVERPROPERTY('Edition') AS nvarchar(100));" -Trust
    }
    if ($r.Ok) {
        Write-Check 'ok' 'SQL Server engine' "$($r.Lines[0]) at $sqlServer, database $sqlDatabase"
        if ($trust) { Write-Check 'WARN' 'SQL encryption' 'connection needed -C (trust server certificate)' }
        else { Write-Check 'ok' 'SQL encryption' 'connects without -C' }

        $list = ($schemas | ForEach-Object { "'$_'" }) -join ','
        $s = Invoke-Sql "SELECT name FROM sys.schemas WHERE name IN ($list);" -Trust:$trust
        $found = @($s.Lines)
        $absent = @($schemas | Where-Object { $found -notcontains $_ })
        if ($s.Ok -and $absent.Count -eq 0) { Write-Check 'ok' 'SQL schemas' ($schemas -join ', ') }
        else { Write-Check 'MISSING' 'SQL schemas' "missing: $($absent -join ', ')" }

        $m = Invoke-Sql "SELECT CAST(value_in_use AS int) FROM sys.configurations WHERE name = 'max server memory (MB)';" -Trust:$trust
        if ($m.Ok -and $m.Lines.Count -gt 0) {
            $mb = [int64]$m.Lines[0]
            if ($mb -ge 2147483647) { Write-Check 'MISSING' 'max server memory (MB)' "$mb (uncapped)" }
            else { Write-Check 'ok' 'max server memory (MB)' "$mb" }
        } else { Write-Check 'MISSING' 'max server memory (MB)' 'could not read' }
    } else {
        Write-Check 'MISSING' 'SQL Server engine' "cannot connect to $sqlServer / $sqlDatabase : $(($r.Lines | Select-Object -First 2) -join ' ')"
        Write-Check 'MISSING' 'SQL schemas' 'not checked (no connection)'
        Write-Check 'MISSING' 'max server memory (MB)' 'not checked (no connection)'
    }
} else {
    Write-Check 'MISSING' 'SQL Server engine' 'not checked (sqlcmd missing)'
    Write-Check 'MISSING' 'SQL schemas' 'not checked (sqlcmd missing)'
    Write-Check 'MISSING' 'max server memory (MB)' 'not checked (sqlcmd missing)'
}

# --- Optional ----------------------------------------------------------------
$as = Get-Service -Name 'MSSQLServerOLAPService' -ErrorAction SilentlyContinue
if ($as) { Write-Check 'ok' 'Analysis Services service' "$($as.Status), start type $($as.StartType)" }
else { Write-Check 'WARN' 'Analysis Services service' 'not installed (optional)' }

$desk = Get-Process -Name 'PBIDesktop' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($desk) { Write-Check 'ok' 'Power BI Desktop running' "pid $($desk.Id)" }
else { Write-Check 'WARN' 'Power BI Desktop running' 'not running (optional)' }

''
if ($script:missing -gt 0) {
    "$($script:missing) required item(s) missing."
    exit 1
}
'All required items present.'
exit 0
