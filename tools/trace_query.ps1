<#
.SYNOPSIS
Runs one .dax file against a model open in Power BI Desktop under a server-side trace and writes the timings,
storage-engine queries, query plans, DirectQuery SQL and aggregation-rewrite results to a JSON file.

.DESCRIPTION
The engine is found the same way as in tools/run_dax.ps1: the msmdsrv.exe child of the PBIDesktop.exe whose
window title matches -WindowTitle.

A trace is created on that engine through the Tabular Object Model, with these event classes:
QueryEnd, VertiPaqSEQueryEnd, VertiPaqSEQueryCacheMatch, DAXQueryPlan, DirectQueryEnd and
AggregateTableRewriteQuery. The query runs over ADOMD.NET, and only events from that connection's session are
kept, so queries the Desktop canvas sends at the same time do not leak into the result. The trace is dropped at the
end, also when the query fails.

Output JSON (one file per run, <OutDir>\<query name><OutSuffix>.json):
  query_file, query_sha256      the file name and a SHA-256 of its text
  cold                          whether the cache was cleared first (XMLA ClearCache)
  rows_returned, error          the result size, or the query error text
  total_ms, total_cpu_ms        from QueryEnd
  se_ms, fe_ms_derived          sum of non-internal VertiPaqSEQueryEnd durations, and total_ms minus that.
                                The split is approximate: storage-engine scans can run in parallel.
  se_query_count, se_cache_hits
  se_queries[]                  subclass, duration_ms, cpu_ms, cached, xmsql (storage-engine query text)
  query_plan.logical/physical   DAXQueryPlan text
  direct_query[]                duration_ms, sql (DirectQueryEnd)
  aggregation_rewrites[]        the AggregateTableRewriteQuery JSON (match found or not, and why)
  unavailable_events[]          event classes the engine refused to trace

Run with Windows PowerShell 5.1 (powershell.exe); the TOM and ADOMD.NET libraries are .NET Framework builds.
TOM is loaded from the Tabular Editor 2 folder, ADOMD.NET from DAX Studio or the ADOMD.NET client install.

.PARAMETER QueryFile
The .dax file to run (required).

.PARAMETER OutDir
Folder for the JSON output. Default tests\traces.

.PARAMETER OutSuffix
Text appended to the output file name, for example _cold.

.PARAMETER WindowTitle
Wildcard matched against the Desktop window title. Default UKGroupFinance*.

.PARAMETER Cold
Clear the engine cache before the query.

.PARAMETER Roles
Comma-separated model roles to apply to the query connection.

.PARAMETER User
User name to impersonate with ActAs (needs -Roles).

.PARAMETER WaitSec
How long to wait for trace events after the query returns. Default 10.

.EXAMPLE
powershell.exe -NoProfile -File tools\trace_query.ps1 -QueryFile tests\perf\outturn_as_at.dax -Cold -OutSuffix _cold

.EXAMPLE
powershell.exe -NoProfile -File tools\trace_query.ps1 -QueryFile tests\agg\hit_month_org.dax -WindowTitle "UKGroupFinance Scale*"
#>
param(
    [Parameter(Mandatory = $true)][string]$QueryFile,
    [string]$OutDir = "tests\traces",
    [string]$OutSuffix = "",
    [string]$WindowTitle = "UKGroupFinance*",
    [switch]$Cold,
    [string]$Roles = "",
    [string]$User = "",
    [int]$WaitSec = 10,
    [string]$TomDir = "",
    [string]$AdomdPath = ""
)
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSEdition -eq "Core") { throw "Run this script with Windows PowerShell 5.1 (powershell.exe), not pwsh." }
if (-not (Test-Path $QueryFile)) { throw "Query file not found: $QueryFile" }
if ($User -and -not $Roles) { throw "-User needs -Roles: without a role no security filter applies." }

if (-not $TomDir) {
    $te = Get-Command TabularEditor.exe -ErrorAction SilentlyContinue
    if ($te) { $TomDir = Split-Path $te.Source }
}
if (-not $TomDir -or -not (Test-Path (Join-Path $TomDir "Microsoft.AnalysisServices.Tabular.dll"))) {
    throw "Microsoft.AnalysisServices.Tabular.dll not found. Pass -TomDir with the Tabular Editor 2 folder."
}
if (-not $AdomdPath) {
    $candidates = @()
    $ds = Get-Command dscmd.exe -ErrorAction SilentlyContinue
    if ($ds) { $candidates += Join-Path (Split-Path $ds.Source) "bin\Microsoft.AnalysisServices.AdomdClient.dll" }
    $candidates += Join-Path $env:LOCALAPPDATA "Programs\DAX Studio\bin\Microsoft.AnalysisServices.AdomdClient.dll"
    $candidates += Get-ChildItem (Join-Path $env:ProgramFiles "Microsoft.NET\ADOMD.NET") -Filter "Microsoft.AnalysisServices.AdomdClient.dll" -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | ForEach-Object { $_.FullName }
    $AdomdPath = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $AdomdPath) { throw "Microsoft.AnalysisServices.AdomdClient.dll not found. Pass -AdomdPath." }

$desktops = @(Get-Process PBIDesktop -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like $WindowTitle })
if ($desktops.Count -eq 0) { throw "No Power BI Desktop window with a title like '$WindowTitle' is open." }
if ($desktops.Count -gt 1) { throw "$($desktops.Count) Desktop windows match '$WindowTitle'. Pass a more specific -WindowTitle." }
$engine = Get-CimInstance Win32_Process -Filter "Name='msmdsrv.exe'" | Where-Object { $_.ParentProcessId -eq $desktops[0].Id } | Select-Object -First 1
if (-not $engine) { throw "Desktop (PID $($desktops[0].Id)) has no Analysis Services engine yet. Wait for the model to load." }
$port = Get-NetTCPConnection -OwningProcess $engine.ProcessId -State Listen | Select-Object -ExpandProperty LocalPort -Unique | Select-Object -First 1
$server = "localhost:$port"

$coreDll = Join-Path $TomDir "Microsoft.AnalysisServices.Core.dll"
$tabularDll = Join-Path $TomDir "Microsoft.AnalysisServices.Tabular.dll"
Add-Type -Path $coreDll
Add-Type -Path $tabularDll
# Add-Type can report a ReflectionTypeLoadException for ADOMD.NET types it does not need; the client still works.
try { Add-Type -Path $AdomdPath } catch [System.Reflection.ReflectionTypeLoadException] { }
if (-not ("TraceQueryCollector" -as [type])) {
    Add-Type -ReferencedAssemblies $coreDll, $tabularDll -TypeDefinition @"
using System;
using System.Collections.Concurrent;
using Microsoft.AnalysisServices.Tabular;
public class TraceQueryRow {
    public string EventClass; public string EventSubclass; public string TextData; public string SessionID;
    public long Duration = -1; public long CpuTime = -1;
}
public class TraceQueryCollector {
    public ConcurrentQueue<TraceQueryRow> Rows = new ConcurrentQueue<TraceQueryRow>();
    public TraceEventHandler Handler() { return new TraceEventHandler(OnEvent); }
    private void OnEvent(object sender, TraceEventArgs e) {
        var r = new TraceQueryRow();
        try { r.EventClass = e.EventClass.ToString(); } catch { }
        try { r.EventSubclass = e.EventSubclass.ToString(); } catch { }
        try { r.TextData = e.TextData; } catch { }
        try { r.SessionID = e.SessionID; } catch { }
        try { r.Duration = e.Duration; } catch { }
        try { r.CpuTime = e.CpuTime; } catch { }
        Rows.Enqueue(r);
    }
}
"@
}

$EC = [Microsoft.AnalysisServices.TraceEventClass]
$TC = [Microsoft.AnalysisServices.TraceColumn]
$timed = @($TC::EventClass, $TC::EventSubclass, $TC::TextData, $TC::SessionID, $TC::Duration, $TC::CpuTime, $TC::StartTime, $TC::EndTime)
$untimed = @($TC::EventClass, $TC::EventSubclass, $TC::TextData, $TC::SessionID, $TC::CurrentTime)
$wanted = [ordered]@{
    "QueryEnd" = $timed; "VertiPaqSEQueryEnd" = $timed; "VertiPaqSEQueryCacheMatch" = $untimed
    "DAXQueryPlan" = $untimed; "DirectQueryEnd" = $timed; "AggregateTableRewriteQuery" = $untimed
}

$tom = New-Object Microsoft.AnalysisServices.Tabular.Server
$tom.Connect($server)
$trace = $null
$conn = $null
$unavailable = @()
try {
    $db = $tom.Databases[0]
    # The first Update creates the trace on the server and needs at least one event (QueryEnd, listed first).
    $trace = $tom.Traces.Add("trace_query_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    foreach ($name in $wanted.Keys) {
        $ev = $trace.Events.Add([Enum]::Parse($EC, $name))
        foreach ($c in $wanted[$name]) { [void]$ev.Columns.Add($c) }
        try { $trace.Update() }
        catch {
            # Retry with the minimum column set before giving up on the event class.
            [void]$trace.Events.Remove($ev)
            $ev = $trace.Events.Add([Enum]::Parse($EC, $name))
            foreach ($c in @($TC::EventClass, $TC::TextData, $TC::SessionID)) { [void]$ev.Columns.Add($c) }
            try { $trace.Update() } catch { [void]$trace.Events.Remove($ev); $trace.Update(); $unavailable += $name }
        }
    }
    $collector = New-Object TraceQueryCollector
    $trace.add_OnEvent($collector.Handler())
    $trace.Start()

    if ($Cold) {
        $clear = '<ClearCache xmlns="http://schemas.microsoft.com/analysisservices/2003/engine"><Object><DatabaseID>' + [Security.SecurityElement]::Escape($db.ID) + '</DatabaseID></Object></ClearCache>'
        $res = $tom.Execute($clear)
        $msgs = @($res | ForEach-Object { $_.Messages } | ForEach-Object { $_.Description })
        if ($msgs.Count -gt 0) { throw "ClearCache failed: $($msgs -join '; ')" }
    }

    $cs = "Data Source=$server;Initial Catalog=$($db.Name)"
    if ($Roles) { $cs += ";Roles=$Roles" }
    if ($User) { $cs += ";Authentication Scheme=ActAs;Ext Auth Info=`"<Properties><UserName>$User</UserName><BypassAuthorization>true</BypassAuthorization><RestrictCatalog>$($db.Name)</RestrictCatalog></Properties>`"" }
    $conn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection($cs)
    $conn.Open()
    $session = $conn.SessionID
    $text = [IO.File]::ReadAllText((Resolve-Path $QueryFile))
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $text
    $rows = 0
    $queryError = $null
    try {
        $reader = $cmd.ExecuteReader()
        while ($reader.Read()) { $rows++ }
        $reader.Close()
    }
    catch { $queryError = $_.Exception.Message }

    $deadline = (Get-Date).AddSeconds($WaitSec)
    do {
        Start-Sleep -Milliseconds 500
        $mine = @($collector.Rows.ToArray() | Where-Object { $_.SessionID -eq $session })
        $done = @($mine | Where-Object { $_.EventClass -eq "QueryEnd" }).Count -gt 0
    } while (-not $done -and (Get-Date) -lt $deadline)
    Start-Sleep -Milliseconds 1500   # late storage-engine and plan events
    $trace.Stop()
    $mine = @($collector.Rows.ToArray() | Where-Object { $_.SessionID -eq $session })
}
finally {
    if ($conn) { $conn.Close() }
    if ($trace) { try { $trace.Stop() } catch { }; try { $trace.Drop() } catch { } }
    $tom.Disconnect()
}

$queryEnd = @($mine | Where-Object { $_.EventClass -eq "QueryEnd" }) | Select-Object -Last 1
$seEnd = @($mine | Where-Object { $_.EventClass -eq "VertiPaqSEQueryEnd" })
$seHits = @($mine | Where-Object { $_.EventClass -eq "VertiPaqSEQueryCacheMatch" })
# A scan answered from the storage-engine cache still raises VertiPaqSEQueryEnd; it is flagged as cached when a
# VertiPaqSEQueryCacheMatch with the same xmSQL text was raised in the same query.
$hitText = @{}
foreach ($e in $seHits) { if ($e.TextData) { $hitText[$e.TextData] = 1 } }
$seList = @()
foreach ($e in $seEnd) { $seList += [ordered]@{ subclass = $e.EventSubclass; duration_ms = $e.Duration; cpu_ms = $e.CpuTime; cached = [bool]($e.TextData -and $hitText.ContainsKey($e.TextData)); xmsql = $e.TextData } }
$seMs = 0
foreach ($e in $seEnd) { if ($e.EventSubclass -notlike "*Internal*" -and $e.Duration -gt 0) { $seMs += $e.Duration } }
$plans = @($mine | Where-Object { $_.EventClass -eq "DAXQueryPlan" })
$rewrites = @()
foreach ($e in @($mine | Where-Object { $_.EventClass -eq "AggregateTableRewriteQuery" })) {
    try { $rewrites += ($e.TextData | ConvertFrom-Json) } catch { $rewrites += $e.TextData }
}
$dq = @()
foreach ($e in @($mine | Where-Object { $_.EventClass -eq "DirectQueryEnd" })) { $dq += [ordered]@{ duration_ms = $e.Duration; cpu_ms = $e.CpuTime; sql = $e.TextData } }

$sha = [Security.Cryptography.SHA256]::Create()
$hash = ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)) | ForEach-Object { $_.ToString("x2") }) -join ""
$total = if ($queryEnd) { $queryEnd.Duration } else { $null }
$result = [ordered]@{
    query_file = (Split-Path $QueryFile -Leaf)
    query_sha256 = $hash
    run_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    cold = [bool]$Cold
    roles = $Roles
    user = $User
    rows_returned = $rows
    error = $queryError
    total_ms = $total
    total_cpu_ms = if ($queryEnd) { $queryEnd.CpuTime } else { $null }
    se_ms = $seMs
    fe_ms_derived = if ($null -ne $total) { [Math]::Max(0, $total - $seMs) } else { $null }
    se_query_count = @($seEnd | Where-Object { $_.EventSubclass -notlike "*Internal*" }).Count
    se_cache_hits = $seHits.Count
    se_queries = $seList
    query_plan = [ordered]@{
        logical = (@($plans | Where-Object { $_.EventSubclass -like "*Logical*" }) | Select-Object -Last 1).TextData
        physical = (@($plans | Where-Object { $_.EventSubclass -like "*Physical*" }) | Select-Object -Last 1).TextData
    }
    direct_query = $dq
    aggregation_rewrites = $rewrites
    unavailable_events = $unavailable
    event_counts = [ordered]@{}
}
foreach ($g in ($mine | Group-Object EventClass)) { $result.event_counts[$g.Name] = $g.Count }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$out = Join-Path $OutDir ([IO.Path]::GetFileNameWithoutExtension($QueryFile) + $OutSuffix + ".json")
[IO.File]::WriteAllText((Join-Path (Resolve-Path $OutDir) (Split-Path $out -Leaf)), ($result | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
$status = if ($queryError) { "QUERY ERROR" } else { "ok" }
Write-Host ("{0,-11} {1} total={2} ms se={3} ms se_queries={4} cache_hits={5} dq={6} rewrites={7} -> {8}" -f $status, $result.query_file, $total, $seMs, $result.se_query_count, $seHits.Count, $dq.Count, $rewrites.Count, $out)
if ($unavailable.Count -gt 0) { Write-Host "            event classes not available: $($unavailable -join ', ')" }
if ($queryError) { Write-Host "            $queryError"; exit 1 }
