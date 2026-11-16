# Local environment

This note records how my local environment is set up for this project and what I tested on it. Every statement is labelled **tested** (with the command) or **designed** (intended behaviour I have not run yet).

To re-check the whole environment at any time:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\check_env.ps1
pwsh -NoProfile -File tools\check_env.ps1
```

The script prints one `ok` / `MISSING` / `WARN` line per item and exits 1 if anything required is missing. It reads the SQL target from `UKFR_SQL_SERVER` (default `localhost`) and `UKFR_SQL_DATABASE` (default `UKGroupFinance`). **Tested:** both commands exit 0 on my machine.

## What is installed

| Component | Version | Where | Status |
|---|---|---|---|
| SQL Server 2022 Developer, Database Engine | 16.0.1000.6 (RTM) | default instance `MSSQLSERVER`, `localhost`, TCP 1433 | tested: `SELECT @@VERSION` |
| SQL Server 2022 Analysis Services, Tabular mode | 16.0.42.209 | default instance, `localhost` | tested: TOM `Server.ServerMode` returns `Tabular` |
| ODBC Driver 17 for SQL Server | 17.4.1.1 | installed by SQL Server setup | tested: `Get-OdbcDriver` |
| ODBC Driver 18 for SQL Server | 18.7.1.1 | winget `Microsoft.msodbcsql.18` | tested: `Get-OdbcDriver` |
| sqlcmd (go-sqlcmd) | 1.10.0 | `C:\Program Files\SqlCmd\sqlcmd.exe`, first on PATH | tested: `Get-Command sqlcmd -All` |
| sqlcmd (ODBC) and bcp | 16.0.1000.6 | `C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\` | tested: `Get-Command bcp` |
| Power BI Desktop (Store), Tabular Editor 2, DAX Studio `dscmd`, `pbir`, `uv`, `git`, `gh` | see `tools\check_env.ps1` output | on PATH / Appx | tested: `tools\check_env.ps1` |

Two `sqlcmd` executables are on PATH. A bare `sqlcmd` runs go-sqlcmd. Both accept the classic flags (`-S -E -d -Q -i -b -W -h -C`) that I use in scripts.

### Install media

The SQL Server 2022 Developer bootstrapper (`SQL2022-SSEI-Dev.exe`) no longer runs. Every official link to it, including the winget package, serves build 16.2211, and it exits with "This version of the installer is no longer supported". I installed from the SQL Server 2022 Developer ISO on download.microsoft.com, which is build 16.0.1000.6, with a valid Microsoft signature on `setup.exe`.

Three install pitfalls I hit, for anyone rebuilding this:

1. The bootstrapper needs administrator rights even for `/Action=Download`, so the download cannot be done before the elevated step.
2. SQL Server setup refuses to start when the path to `setup.exe` is long. Its `MediaPathLength` rule failed at 136 characters, even though the message talks about 260. Running `setup.exe` from the root of the mounted ISO avoids it.
3. The winget `Microsoft.Sqlcmd` package is go-sqlcmd and does not include `bcp`. In my case `bcp` came with SQL Server setup itself, along with ODBC Driver 17.

### Setup command

**Tested** (run once, elevated, from the mounted ISO; setup exit code 0, every feature `Passed` in `Summary.txt`):

```text
setup.exe /Q /ACTION=Install /IACCEPTSQLSERVERLICENSETERMS /FEATURES=SQLENGINE,AS
  /INSTANCENAME=MSSQLSERVER /ASSERVERMODE=TABULAR
  /SQLSYSADMINACCOUNTS="<machine>\<user>" /ASSYSADMINACCOUNTS="<machine>\<user>"
  /TCPENABLED=1 /SQLSVCSTARTUPTYPE=Automatic /ASSVCSTARTUPTYPE=Manual
  /UPDATEENABLED=False /INDICATEPROGRESS
```

My Windows account is sysadmin on the engine and server administrator on Analysis Services. Both services run as their default virtual accounts (`NT Service\MSSQLSERVER` for the engine).

## Instance and database

- Engine: `localhost` (default instance), Windows authentication only.
- Database `UKGroupFinance`, simple recovery, data and log files in the instance's default data directory (`...\MSSQL16.MSSQLSERVER\MSSQL\DATA\`). **Tested:** `sys.databases`, `sys.master_files`.
- Schemas: `raw`, `stg`, `dw`, `authored`, `synthetic`, `scale`, `quarantine`, `audit`. **Tested:** `SELECT name FROM sys.schemas`.
- TCP is enabled. **Tested:** `sys.dm_exec_connections` for my session shows `net_transport = TCP`, `local_tcp_port = 1433`, `auth_scheme = NTLM`.

## Memory cap

`max server memory (MB)` is 8192. Power BI Desktop's own Analysis Services engine and SQL Server share 31 GB of RAM on this machine. Uncapped, SQL Server takes memory as its buffer pool grows and does not hand it back quickly, which would starve Desktop during refreshes and benchmarks. 8 GB is plenty for the data volumes in this project.

**Tested:**

```sql
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'max server memory (MB)', 8192; RECONFIGURE;
SELECT value_in_use FROM sys.configurations WHERE name = 'max server memory (MB)';  -- 8192
```

## Load permissions: bcp vs BULK INSERT

I loaded a three-row CSV from a folder under my user profile into a scratch table `raw.ukfr_load_probe` three ways, then dropped the table.

| Method | Runs file access as | Result |
|---|---|---|
| `bcp raw.ukfr_load_probe in <csv> -S localhost -T -d UKGroupFinance -c -t, -F 2` | my Windows user (client side) | **tested:** 3 rows copied |
| `BULK INSERT raw.ukfr_load_probe FROM '<csv>' WITH (FORMAT='CSV', FIRSTROW=2)` | my Windows login, impersonated by the server | **tested:** 3 rows affected |
| Python `pyodbc` `executemany` through ODBC Driver 18 (`uv run --no-project --with pyodbc`) | my Windows user (client side) | **tested:** 3 rows inserted |

The total afterwards was 9 rows with amounts summing to 249.7500 (3 × 83.25), so all three loads landed intact as `DECIMAL(19,4)`.

My expectation was that `BULK INSERT` would fail with access denied because the engine runs as `NT Service\MSSQLSERVER`. It did not. With a Windows-authenticated login, SQL Server impersonates the caller when it opens the file, so a local file I can read loads fine. This would not hold for a SQL login, or for a file on a network share (that needs delegation). The loader can use any of the three. I will keep client-side loading (pyodbc or bcp) as the default so the design does not depend on server-side file access.

## Extended Events

My login holds `ALTER ANY EVENT SESSION`. **Tested:** `SELECT HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION')` returns 1, and `IS_SRVROLEMEMBER('sysadmin')` returns 1.

**Tested** end to end with a short T-SQL script run through `sqlcmd -S localhost -E -b -i <script>`. The script:

1. creates a session capturing `sqlserver.sql_batch_completed` to a `package0.ring_buffer` target;
2. starts it and runs a probe batch;
3. reads the ring buffer, which showed `eventCount = 2`;
4. stops and drops the session, after which no session of that name remained.

So the query-folding evidence planned for later (capturing the SQL that Power BI sends) is possible on this instance.

## Encryption and trust

The engine uses its self-generated certificate, which no client trusts.

- **Tested:** `sqlcmd -S localhost -E` (go-sqlcmd) and the ODBC `SQLCMD.EXE -S localhost -E` both connect **without** `-C`. They do not request encryption by default, and `encrypt_option` for the session is `FALSE`.
- **Tested:** forcing encryption without trusting the certificate fails. `SQLCMD.EXE -S localhost -E -N` returns "SSL Provider: The certificate chain was issued by an authority that is not trusted".
- **Tested:** pyodbc with ODBC Driver 18 needs `TrustServerCertificate=yes`, because Driver 18 encrypts by default.

**Designed, not yet tested** in Power BI Desktop. Desktop's SQL Server connector tries an encrypted connection first, so the first connection to `localhost` / `UKGroupFinance` is expected to show:

1. the credential dialog: choose **Windows** → **Use my current credentials** → **Connect**;
2. an encryption-support message saying the encrypted connection failed: choose **OK** to connect unencrypted.

The unencrypted connection is acceptable here because it never leaves the machine. Desktop remembers the choice per data source (File → Options and settings → Data source settings → Edit Permissions → "Encrypt connections" unticked).

**Tested** in the Desktop spike ([desktop_capabilities.md](desktop_capabilities.md), rows 2a–2c): Desktop's traces show a failed encrypted attempt followed by an unencrypted connection once the dialogs were answered. The choice then held for a second project and for later sessions. I did not capture the dialogs' exact wording.

## Analysis Services service

The service `MSSQLServerOLAPService` is set to **Manual** start and is only needed in Phase 5. **Tested:**

- `Get-Service MSSQLServerOLAPService` shows `StartType Manual`;
- TOM (`Microsoft.AnalysisServices.Tabular.Server.Connect('Data Source=localhost')` from Windows PowerShell 5.1, using the DLLs in the Tabular Editor 2 folder) reports `ServerMode = Tabular`, edition Developer64.

Starting and stopping a Windows service needs an elevated shell:

```powershell
Start-Service MSSQLServerOLAPService   # elevated
Stop-Service  MSSQLServerOLAPService   # elevated
```

Setup left the service running after install, and from a non-elevated shell `Stop-Service` fails with "Cannot open 'MSSQLServerOLAPService' service". It stays stopped after the next restart because the start type is Manual.
