# CI spike: model lint, SQL container load, report checks

I ran this spike on 16 November 2026 to answer three questions before the project's CI gets built on them:

1. Can Tabular Editor 2's Best Practice Analyzer lint TMDL on a GitHub-hosted Windows runner, and can I control which severities fail the build?
2. Can a SQL Server 2022 container on an Ubuntu runner be loaded from a UTF-8 CSV with quoted fields and checked against control totals, and which loader works the same on Windows and Linux?
3. Can report-definition rules run from the command line against a PBIR report, and does a failed rule fail the job?

All three are proven on fixtures under `tests/fixtures/ci_spike/`. The workflow is `.github/workflows/ci.yml`; it runs on pull requests and on pushes to `main`.

Runner images seen: `windows-2025-vs2026` 20261103.298.1 and `ubuntu-26.04` 20261111.196.1 (`ubuntu-latest` already points at 26.04).

## Runs

| Run | Commit | Result | What it shows |
|---|---|---|---|
| [43961675854](https://github.com/Shivansh9307/uk-group-finance-reporting/actions/runs/43961675854) | 405d8bb | model-bpa failed | The planted violation (measure with no description, severity 3) fails the job |
| [43962287065](https://github.com/Shivansh9307/uk-group-finance-reporting/actions/runs/43962287065) | 1919a2d | model-bpa, report-checks failed | Report gate needed `-verbose true` |
| [43962529910](https://github.com/Shivansh9307/uk-group-finance-reporting/actions/runs/43962529910) | 9b62609 | model-bpa failed | Planted violation still fails; other two jobs green |
| [43962782553](https://github.com/Shivansh9307/uk-group-finance-reporting/actions/runs/43962782553) | 562abb2 | all green | Measure described; the severity 2 and 1 findings remain and only warn |

## Findings

| Question | Answer | Evidence | Status |
|---|---|---|---|
| TE2 portable build for 2.29.0 | Published as `TabularEditor.Portable.zip`, sha256 `c0d3a7ab…08a4` (matches the release digest). Download and verify takes 1.7 s; cached afterwards | run 43961675854, "Download Tabular Editor 2 portable" | tested |
| Command line that loads TMDL | `TabularEditor.exe <path>\Minimal.SemanticModel\definition -A bpa-rules.json -G -T results.trx`. Passing `definition\database.tmdl` also works. The `.SemanticModel` folder fails ("File not found"), and a `.pbip` fails because TE2 looks for `model.bim` beside it | local runs with TE2 2.29.0; CI step "Best Practice Analyzer" | tested |
| Compatibility level | 1600, 1606 and 1702 all load in CI; locally 1600–1607, 1650, 1700 and even 9999 load. TE2 does not check the level when it reads TMDL, so the real limit is whether the TMDL uses syntax its TOM build cannot parse. A model saved by Desktop 2.159 at 1606 (from my earlier project) loads and analyses cleanly | CI step "Check which compatibility levels TE2 loads"; local run | tested (new TMDL features above 1606 not tested) |
| Exit code by severity | Severity 1: plain console line, exit 0. Severity 2: `::warning::` with `-G`, exit 0. Severity 3 or more (4 and 5 too): `::error::`, exit 1 | local runs with one rule at each severity; run 43961675854 | tested |
| Fail at a threshold, warn below | `.github/scripts/run-bpa.ps1` reads the per-rule severity and outcome from the TRX file (`-T`) and exits 1 only for failures at or above `BPA_FAIL_AT_SEVERITY`. Thresholds 2, 3, 4 give exit 1, 1, 0 on the planted fixture | local runs; runs 43961675854 and 43962782553 | tested |
| Rules file line endings | An LF-only rules file loads in TE2 2.29.0; the CRLF requirement I had read about did not show up | local run | tested |
| SQL container start to ready | 3.2–4.3 s from `docker run` to "ready for client connections" in the log; first login succeeded on the first attempt (8.5–12 s after start, because the driver install ran in between). Image pull 5.8–7.4 s | runs 43962287065, 43962782553 | tested |
| sqlcmd / bcp on the runner | Not installed on `ubuntu-26.04`; no ODBC driver either. `mssql-tools18` from Microsoft's apt repo (which pulls in `msodbcsql18`) installs in 7.8–29.8 s, to `/opt/mssql-tools18/bin` (sqlcmd 18.7) | "Probe client tools", "Install mssql-tools18" | tested |
| bcp straight from the CSV | Fails: `-t,` splits inside quoted fields, every row errors with "Invalid character value for cast specification" | load A | tested |
| bcp after normalising to TSV | Works: rows, SUM(amount), £ and non-breaking-space counts all match, with or without `-C 65001`, in 0.02 s. Flags: `-c -t '\t' -r '\n' -u` (plus `-C 65001` to be explicit) | loads B1 and B2 | tested |
| BULK INSERT `FORMAT = 'CSV'` | `CODEPAGE` is rejected on Linux (Msg 16202). Without it the rows and the sum load, but every £ and non-breaking space is lost. The file also has to be copied into the container | load C | tested |
| Python loader | `pyodbc` 5.5.0 + ODBC Driver 18 and `mssql-python` 1.17.0 both load the CSV and match all four control values. `pyodbc` needs the system ODBC driver; `mssql-python` connected before any Microsoft package was installed. Driver install (venv + pip) 5.1–7.0 s | loads D and E; "Probe Python drivers…" | tested |
| Windows side of the Python loader | Not run on a Windows runner or against the local instance in this spike | — | not tested |
| PBI-Inspector status | The project is now **Fab Inspector** (`NatVanG/fab-inspector`; the PBI-InspectorV2 URL redirects there), MIT licence, CLI v4.0.0 published 8 Nov 2026 (marked pre-release), commits in November 2026. Needs the .NET 10 runtime, which `ubuntu-26.04` already has (10.0.8–10.0.15) | `gh repo view`, "Probe .NET runtimes" | tested |
| Fab Inspector install | Download the `linux-x64-FabInspCLI.zip` release asset, check its sha256, unzip, `chmod +x`: 0.9–1.2 s, then cached | "Download Fab Inspector CLI" | tested |
| Fab Inspector exit code | With `-formats Console,JSON` it exits **0 even when an error-level rule fails**. With `-formats GitHub` it exits 1 on a failure, but then writes no JSON file. With `-verbose false` (default) a clean run writes no JSON file either | run 43962529910: "exit code with -formats GitHub: 1"; negative-control log | tested |
| Fab Inspector output | Console text, a JSON file `TestRun_<id>.json` (one result per rule and page: `RuleId`, `Pass`, `LogType` 0 = error, `ParentDisplayName`), HTML, PNG wireframes, ADO or GitHub annotations | negative-control artifact | tested (HTML and PNG not opened) |
| Report gate | `.github/scripts/run-report-rules.sh` runs `-formats Console,JSON -verbose true` and fails on any failed rule with `LogType` 0. A negative-control rules file (max one visual per page) proves the gate fails | runs 43962529910, 43962782553 | tested |
| PBIR fixture without Desktop | Built with `pbir` 0.9.33 only: `new report --thick --no-title`, `report rebind --local ../Minimal.SemanticModel`, two `add visual`, `set …displayName`; `pbir validate --all` passes. I did not open it in Desktop | commands above | tested (rendering not tested) |

## Timings per job (wall clock from GitHub)

| Job | Cold cache | Warm cache |
|---|---|---|
| model-bpa (Windows) | 34 s | 27–37 s |
| pipeline-sql (Ubuntu) | 41 s | 36–64 s (the apt install varies most) |
| report-checks (Ubuntu) | 11 s | 9–13 s |

## Recommendation for the loader

I recommend loading through Python with `mssql-python`, reading the CSV with the standard `csv` module and inserting with `executemany`. It handles RFC 4180 quoting and UTF-8 the same on both platforms, needs no system ODBC driver, keeps the password out of the process list, and needs no file inside the server's filesystem. `pyodbc` with ODBC Driver 18 is an equal fallback where ODBC Driver 18 is already installed. bcp works only after rewriting the file to a delimiter that cannot appear in the data, and it takes the password as `-P` on the command line. BULK INSERT loses non-ASCII characters on Linux. The Windows side of this is not tested yet; the first pipeline task should run the same loader against the local instance.

## What did not work, and what a later task must know

- `services:` cannot read the workflow-level `env` context, and neither can a job-level `env`, so I start the container with `docker run` in a step and copy the password into `SQLCMDPASSWORD` through `GITHUB_ENV`. The workflow-level value is shown in plain text in the env listing of every step until the first step masks it. That is acceptable for a throwaway password in a public file, but a later task could generate it at runtime instead.
- `actions/cache` only saves the cache when the whole job succeeds, so a failing BPA run never cached TE2. I use `actions/cache/restore` and `actions/cache/save` as separate steps.
- Fab Inspector's exit code cannot be trusted with `Console` or `JSON` output; gate on the JSON file.
- The alt-text rule I first wanted needs `visualContainerObjects.general.altText`, which `pbir set` does not expose (`Component 'general' has no property 'altText'`), so I used a visuals-per-page rule instead.
- The steps for loads A and C fail on purpose and are `continue-on-error`, so a green run still carries their error annotations.
- Pass TE2 paths without a trailing backslash; in PowerShell a quoted `"…\"` can escape the closing quote.
