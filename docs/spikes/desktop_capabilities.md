# Power BI Desktop capability spike

I built a throwaway model on this machine to find out which semantic-model features and evidence-capture methods
work with Power BI Desktop alone, before the real model depends on them. This note records what I ran and what
happened. Every row is labelled **tested** (with its evidence file) or **not tested** (with the reason).

Setup: Power BI Desktop, Microsoft Store build 2.159.1231.0, engine version 17.0.93.23. Tabular Editor 2.29.0
(the TOM assembly in its folder reports version 19.117). DAX Studio `dscmd` 3.6.2. SQL Server 2022 on `localhost`.
Nobody was signed in to Desktop, and I changed no Desktop options.

The spike model itself was not kept. It had about 2 million generated fact rows (36 months x 200 organisations x
100 accounts, `DECIMAL(19,4)` amounts, clustered columnstore), three dimensions, a month x organisation
pre-aggregate and a synthetic user-to-organisation table. All of these were scratch objects named `spike_*` in `dw`
and `synthetic`, and I dropped them afterwards. There were two projects: `Spike` (Import, compatibility level 1702)
and `SpikeAgg` (DirectQuery detail, Import aggregate, Dual dimensions). I wrote the TMDL by hand and made the
report parts with `pbir new report` and `pbir report rebind --local`. Evidence is under
[`evidence/desktop/`](evidence/desktop/).

## Verdict

- **Can rely on:** hand-written TMDL at compatibility level 1702 with calculation groups (including format-string
  expressions), dynamic format strings, field parameters, DAX user-defined functions, OFFSET/WINDOW/RANK, dynamic
  RLS, OLS, perspectives, a refresh policy and hand-written multi-partition tables all open in the Store build and
  query correctly. Tabular Editor 2 loads and saves all of it, and its BPA runs on it. Traces capture every event
  class the plan needs, including aggregation rewrites and DirectQuery SQL. Folding shows up in Extended Events.
  Projects open, reload, refresh and close from the command line.
- **Cannot rely on:**
  - Desktop never applies a refresh policy. Any refresh that tries to apply it fails with "An unexpected exception
    occurred", so every refresh must pass `applyRefreshPolicy: false`; `tools/run_dax.ps1` does that.
  - Perspectives are not a security boundary.
  - An aggregation whose column data type differs from the detail column is silently ignored.
  - Loaded data is lost whenever Desktop closes without saving.
- **Clicks:** none for `localhost` / `UKGroupFinance` from now on, because the credential and the unencrypted choice
  are stored. Any new data source (for example a file path for the deflator workbooks, or another server name) will
  ask again. Closing Desktop with unsaved changes through `CloseMainWindow` shows a save prompt, so the tools close
  it with `Stop-Process` instead.

## Matrix

| # | Feature / question | Result | Evidence | What it means for the build |
|---|---|---|---|---|
| 1a | `Start-Process <file>.pbip` opens the Store build | works (tested) | [refresh_and_lifecycle.txt](evidence/desktop/refresh_and_lifecycle.txt) | Open projects this way; `powerbi-desktop open` is not needed. |
| 1b | Time until the engine port can be found | works (tested): 3.3–4.7 s to a listening `msmdsrv.exe` child; 12–15 s until the window title is the project name | same file | Tools must wait for the title, not just the port. The title stays `Untitled - Power BI Desktop` when the load fails. |
| 1c | Second Desktop instance alongside, targeted by window title | works (tested): `Spike` and `SpikeAgg` ran together; each tool call picked its instance by `-WindowTitle` | traces `trace_agg_*.json` were taken with both open | Give the scale project a distinct name. The tools refuse a title pattern that matches two windows. |
| 1d | Close without a blocking prompt and without file writes | works with caveat (tested): `Stop-Process` closes with no prompt and changes no file; `CloseMainWindow` shows "Do you want to save your changes?" (Save / Don't save / Cancel) when a refresh has run, and closes cleanly when nothing is unsaved | [dialogs.txt](evidence/desktop/dialogs.txt), [hash_stability.txt](evidence/desktop/hash_stability.txt) | Close with `Stop-Process -Id <pid>`. Never leave Desktop with a pending save prompt. |
| 2a | What the first SQL Server connection shows | works with caveat (tested, wording not captured): Desktop first tries an encrypted connection, fails (`ResourceEncryptedConnectionException`), then connects unencrypted once the owner has clicked through | [dialogs.txt](evidence/desktop/dialogs.txt) item 4 | Click sequence below. |
| 2b | Can a refresh requested through TOM succeed before any credential is stored? | works with caveat (tested): a TMSL refresh of one table waited about 113 s while the dialogs were answered in Desktop, then succeeded. My two earlier full-model attempts failed for other reasons (rows 3m and 10b), so I did not see a clean "no credential" error | same | A first refresh from the command line can hang until someone clicks. Tools should not be run unattended against a new source. |
| 2c | Credential persists for later sessions and for a second project | works (tested): no dialog when `SpikeAgg` refreshed against the same server and database, nor after closing and reopening `Spike` | [refresh_and_lifecycle.txt](evidence/desktop/refresh_and_lifecycle.txt) | One click-through per data source, not per project. |
| 2d | Data survives closing without saving | fails, as expected (tested): every partition `NoData` after reopen; full refresh of the 2 M-row spike took 6.8–12.4 s | same | Every session starts with `run_dax.ps1 -Refresh`. |
| 3a | Import tables by navigation with `Server`/`Database` M parameters | works (tested) | [feature_results.txt](evidence/desktop/feature_results.txt) q00 | As planned. |
| 3b | Date table, relationships, base measures | works (tested): 2,000,000 rows, 5,998,824,487.94, equal to SQL | same, [sql_baselines.txt](evidence/desktop/sql_baselines.txt) | |
| 3c | Calculation group (Current, YTD, PY, YoY %) with a format-string expression on one item | works (tested): values equal SQL; the `YoY %` item returns format string `0.0%` (MDX cell properties) | feature_results.txt q01 and the MDX section | Needs level 1500 (ordinal). |
| 3d | Measure with `formatStringDefinition` | works with caveat (tested): the expression picks the right branch per cell. The engine's own `FORMATTED_VALUE` ignores scaling commas (`#,0.0,," m"` shows unscaled digits); I did not check a report visual | feature_results.txt, MDX section | Needs level 1601. Check scaled formats on the canvas, not through DAX/MDX. |
| 3e | Field parameter (three columns, `ParameterMetadata`, sort-by, group-by) | works with caveat (tested at model level): table loads, rows and `NAMEOF` values are correct. Not tested on the canvas (no visual built) | feature_results.txt q03 | Model metadata is right. The slicer behaviour is still to be seen in the report task. |
| 3f | DAX user-defined function used by a measure | works (tested). Call it unquoted: `Spike.SafeDivide(x, y)`; `'Spike.SafeDivide'(x, y)` is a syntax error | feature_results.txt q04 | Needs level 1702; below that Desktop refuses to open the project (dialogs.txt item 2). |
| 3g | OFFSET, WINDOW, RANK | works (tested): previous month, rolling three months and the top-five rank all equal SQL | feature_results.txt q05, q06 | |
| 3h | Roles, perspectives, refresh policy, multi-partition table | see rows 6, 7 and 10 | | |
| 3i | Preview-feature switch needed? | not tested: everything loaded with Desktop's current options; I could not read the Options > Preview features state from any settings file without the GUI | | If a later model fails on functions, check File > Options and settings > Options > Preview features first. |
| 3j | What Desktop does when the level is too low | tested: (1) when an object needs a higher level (a function at 1567), an "Issues were found" dialog appears, the model does not load and the window stays Untitled; (2) a model at 1567 with no such object loads and the engine reports 1606 (raised in memory, file unchanged) | dialogs.txt, [compat_levels.txt](evidence/desktop/compat_levels.txt) | Use 1702 (reasoning below). |
| 3k | Measure named like a column of the same table (`Amount` vs `amount`) | fails (tested): "Issues were found … a column with the same name already exists"; the check is case-insensitive | dialogs.txt item 1 | Name base columns differently from measures. |
| 3m | One measure with a DAX error | fails (tested): a full refresh through TOM failed for the whole model until the measure was fixed | refresh_and_lifecycle.txt | Validate measures before refreshing; one broken measure blocks every test. |
| 4a | Tabular Editor 2.29 loads the TMDL folder (function, field parameter, refresh policy, calculation-item format expressions, OLS, `alternateOf`, Dual/DirectQuery partitions) | works (tested), from the `definition` folder | [te2_roundtrip.txt](evidence/desktop/te2_roundtrip.txt) | CI lint can run on the real model unchanged. |
| 4b | Script sets a description on every measure and saves back to TMDL: is the diff limited to the descriptions? | works with caveat (tested). Semantically, the only extra change is an `annotation __TEdtr = 1` on the model. Textually, TE2 also adds `ref role` / `ref perspective` lines, `compatibilityMode: powerBI`, blank lines, rewrites ```` ``` ```` blocks as indented blocks and moves `refreshPolicy` | same | Do not round-trip committed TMDL through TE2 without reviewing the diff. Keep TE2 for lint and for scripted edits followed by a diff review. |
| 4c | Best Practice Analyzer runs on it | works (tested): 3-rule file, violations listed, exit 1 at severity 3 | same | |
| 4d | Object types TE2 fails on | none found (tested) | same | No lint-only copy of the model is needed. |
| 5a | Edit TMDL on disk, then `pbir desktop refresh <Report> --model` | works (tested): about 2 s; a new measure became queryable, a broken measure was fixed, and no project file was rewritten (hashes identical), also with Desktop showing unsaved changes | [hash_stability.txt](evidence/desktop/hash_stability.txt), feature_results.txt q12 | The planned edit-reload loop works without restarting Desktop. A reload keeps loaded data. |
| 5b | Queryable through `dscmd` after a TOM data refresh | works (tested) | all feature results | |
| 6 | Perspectives with `Cube=<name>` | works with caveat (tested): the name is checked (a bogus name fails), and `MDSCHEMA_MEASURES` lists only the perspective's measures under that cube. DAX and MDX queries can still use objects outside the perspective | [perspective_results.txt](evidence/desktop/perspective_results.txt) | Perspectives are a browsing aid only; `-Perspective` cannot prove that an object is hidden. |
| 7a | Dynamic RLS on `USERPRINCIPALNAME()` with `Roles=` and ActAs | works (tested): alice (3 orgs) and bob (1 org) equal SQL; an unmapped user sees nothing | [security_results.txt](evidence/desktop/security_results.txt) | As planned. |
| 7b | `Roles=` without ActAs | works with caveat (tested): the identity is `<machine>\<user>` (local account, nobody signed in), so it matched no row | same | RLS tests must always pass `-User`. |
| 7c | OLS: query on the secured column | fails as designed (tested): "Column 'Paybill Cost' in table 'Organisation' cannot be found or may not be used in this expression." | same | |
| 7d | OLS: measure that references the secured column | fails as designed (tested): an error, not a blank: "The value for 'Paybill Total (OLS)' cannot be determined. Either the column doesn't exist, or there is no current row for this column." Measures not touching the column still answer | same | Every query that touches a paybill measure errors for restricted users, so test files must split restricted and unrestricted measures. |
| 7e | One role with both the RLS filter and the OLS restriction | works (tested) | same | |
| 7f | RLS role plus a separate OLS role together | fails (tested): "The combination of active roles results in a dynamic security configuration that is currently not supported." | same | Put RLS and OLS for a user in one combined role. |
| 8a | `QueryEnd` (duration) | works (tested) | [trace_basic_cold.json](evidence/desktop/trace_basic_cold.json) | |
| 8b | `VertiPaqSEQueryEnd` with duration, and cache matches | works (tested): xmSQL text, duration and subclass; `VertiPaqSEQueryCacheMatch` arrives on warm runs | trace_basic_warm.json | |
| 8c | `DAXQueryPlan` logical and physical | works (tested) | trace_basic_cold.json | |
| 8d | `DirectQueryEnd` with SQL text | works (tested) | [trace_agg_miss.json](evidence/desktop/trace_agg_miss.json) | |
| 8e | `AggregateTableRewriteQuery` | works (tested): `matchFound` with the mapping, or `attemptFailed` with the reason | trace_agg_hit.json, trace_agg_miss.json | No event class was unavailable from the local engine. |
| 9a | Aggregation hit (month x organisation) | works (tested): `matchFound` mapped to `Sales Agg`; no SQL reached SQL Server | trace_agg_hit.json, [xe_agg_hit.csv](evidence/desktop/xe_agg_hit.csv) (header only) | |
| 9b | Aggregation miss (by account) | works (tested): `attemptFailed`, "no column mapping" for `Account[Account Class]`; `DirectQueryEnd` carries the SQL, and it arrived at SQL Server from "Framework Microsoft SqlClient Data Provider" (schema probes come from "Mashup Engine") | trace_agg_miss.json, [xe_agg_miss.csv](evidence/desktop/xe_agg_miss.csv) | |
| 9c | What a hit needs | tested: it hit on the first try with many-to-one relationships from both the aggregate and the detail to Dual dimensions, `decimal` on both amount columns and a `count` mapping with `baseTable`. With the aggregate column changed to `double`, Desktop loaded with no warning and the rewrite reported "missing aggregation", falling through to DirectQuery | [trace_agg_type_mismatch.json](evidence/desktop/trace_agg_type_mismatch.json) | Data types must match exactly, and only a rewrite trace shows a mismatch, so add a trace test for every aggregation. |
| 10a | `RangeStart`/`RangeEnd` filter folds | works (tested): `where [_].[load_date] >= convert(datetime2, '2023-04-01 00:00:00') and [_].[load_date] < convert(datetime2, '2026-04-01 00:00:00')` | [xe_refresh_sql.csv](evidence/desktop/xe_refresh_sql.csv) | |
| 10b | What Desktop does with `refreshPolicy` | works with caveat (tested): the policy is kept (read back from the engine), no partitions are created, and the polling expression never ran. A refresh that tries to apply the policy (TOM `RequestRefresh`, or TMSL without `applyRefreshPolicy: false`) fails with "An unexpected exception occurred" | refresh_and_lifecycle.txt | The policy is design evidence plus folding proof only, as the plan already says. Refresh with `applyRefreshPolicy: false`. |
| 10c | Policy in the Incremental refresh dialog | not tested: needs a person to open the dialog | | Optional check for the owner. |
| 10d | Table with three hand-written M partitions | works (tested): opens, refreshes, one `where [month_key] = …` query per partition, row counts equal SQL | feature_results.txt q11, xe_refresh_sql.csv | Scripted monthly partitions are possible in Desktop itself, not only on the Analysis Services side-car. |
| 11a | `dscmd csv` | works (tested) | all feature results | |
| 11b | `dscmd benchmark` output | works (tested): columns `Sequence, Cache, TotalDuration_ms, FormulaEngineDuration_ms, StorageEngineDuration_ms, StorageEngineQueryCount, StorageEngineCpu_ms, TotalCpu_ms, VertipaqCacheMatches, RowCount, Error`, then a summary block (average, standard deviation, min, max per cold/warm). Works under a role too. One cold run reported 0 storage-engine queries | [benchmark_sample.csv](evidence/desktop/benchmark_sample.csv) | The file has a byte-order mark and two blocks; parse both. Use medians and cross-check odd runs with `trace_query.ps1`. |
| 11c | `dscmd vpax`; which file holds sizes; local paths | works (tested): `DaxModel.json` holds per-column cardinality, encoding and dictionary/data/hierarchy sizes; `DaxVpaView.json` holds flattened table and column sizes. This spike's file had no local path or machine name, but `ServerName` holds `localhost:<port>` and `Model.bim` holds the full M source, so a real model's file-path parameters would appear | [vpax/](evidence/desktop/vpax/) via `tools/vpax_summary.py` | Commit only the CSV summary. |
| 12 | Files change on disk without a Save? | no (tested): 27 Spike files unchanged across about 30 minutes open, a refresh, many queries, a reload, a declined save prompt and `Stop-Process`; Desktop created no `.pbi` folder or `cache.abf` | [hash_stability.txt](evidence/desktop/hash_stability.txt) | The evidence-ledger hash is stable as long as nobody presses Save. |

## First connection: what to click

The owner clicked through this during the spike. From the traces, the sequence is the one expected in
[environment.md](environment.md):

1. A credential dialog for `localhost;UKGroupFinance`: choose **Windows**, then **Use my current credentials**,
   then **Connect**.
2. An encryption-support message saying the encrypted connection failed: choose **OK** to connect unencrypted.

I was not polling the windows at that moment, so I did not capture the exact wording. The trace timings in
[dialogs.txt](evidence/desktop/dialogs.txt) confirm the two steps: an encrypted attempt failed, then an
unencrypted one succeeded. The choice is stored per data source. Nothing more should be needed for this server and
database.

## Compatibility level

The real model should use **1702**. I chose it because DAX user-defined functions need it: TOM refuses to load a
function below 1702, and Desktop shows the error and opens nothing. Desktop accepted 1702 as written.

The other features need less (tested offline, [compat_levels.txt](evidence/desktop/compat_levels.txt)):

| Feature | Minimum level |
|---|---|
| Calculation groups (with `ordinal`) | 1500 |
| `sourceQueryCulture` on the model | 1520 |
| Measure `formatStringDefinition` | 1601 |
| DAX functions | 1702 |

Desktop itself raised a 1567 model to 1606 when it loaded it. If the plan drops functions, 1606 is the floor.

## Working command lines (tested)

```powershell
# open and wait (title = project name)
Start-Process .\Spike.pbip
# data refresh through TMSL with applyRefreshPolicy false, then run every query file
powershell.exe -NoProfile -File tools\run_dax.ps1 -WindowTitle "Spike" -QueryDir <dir> -OutDir <dir> -Refresh
# RLS as a synthetic user
powershell.exe -NoProfile -File tools\run_dax.ps1 -WindowTitle "Spike" -Filter "q08*.dax" -Roles "RLS Org" -User "alice@spike.example" -OutSuffix _alice
# perspective (metadata only, see row 6)
powershell.exe -NoProfile -File tools\run_dax.ps1 -WindowTitle "Spike" -Filter "q09*.dax" -Perspective Finance
# benchmark and VertiPaq export
powershell.exe -NoProfile -File tools\run_dax.ps1 -WindowTitle "Spike" -Filter "q10*.dax" -Benchmark -Cold 5 -Warm 5
powershell.exe -NoProfile -File tools\run_dax.ps1 -WindowTitle "Spike" -Vpax <file>.vpax
uv run tools/vpax_summary.py <file>.vpax --out-dir <dir>
# one query under a trace, cold cache
powershell.exe -NoProfile -File tools\trace_query.ps1 -WindowTitle "SpikeAgg" -QueryFile <file>.dax -OutDir <dir> -Cold
# reload TMDL edits into the open Desktop without touching files
pbir desktop refresh <Name>.Report --model
# Tabular Editor 2: load from the definition folder, script, save; BPA
TabularEditor.exe <Name>.SemanticModel\definition -S <script>.csx -TMDL <out folder>
TabularEditor.exe <Name>.SemanticModel\definition -A <rules>.json
# close without a prompt
Stop-Process -Id <PBIDesktop pid>
```

Help for the tools: `powershell.exe -NoProfile -Command "Get-Help .\tools\run_dax.ps1 -Full"`.
`-File tools\run_dax.ps1 -?` prints nothing under Windows PowerShell 5.1.

## What failed and the consequence

- **Refresh policy in Desktop:** stored, never applied, and any refresh that applies it errors. Consequence: the
  refresh policy stays a TMDL design artefact plus a folding proof, and every scripted refresh passes
  `applyRefreshPolicy: false`, which `run_dax.ps1` already does.
- **Perspectives restrict metadata only.** Consequence: no test may use a perspective as evidence that an object is
  hidden. OLS does that.
- **RLS role combined with a separate OLS role** errors at query time. Consequence: one combined role per audience
  (for example "Department finance, no paybill").
- **OLS makes referencing measures error, not blank.** Consequence: RLS/OLS test files keep restricted measures in
  separate queries, and the expected result for a restricted user is the error text.
- **Aggregation with mismatched data types** is accepted silently and never used. Consequence: each aggregation gets
  a trace test on `matchingResult`.
- **Data is lost when Desktop closes.** Consequence: every session refreshes first; the 100 M-row scale table will
  need its own timing.
- **TE2 rewrites more than it is asked to.** Consequence: scripted edits are reviewed as diffs. I would not let TE2
  save over hand-written TMDL as a formatting step.

## Rules for model authors

1. Set `compatibilityLevel: 1702` in `database.tmdl`.
2. Never give a measure the name of a column in its own table, in any letter case.
3. Call DAX functions unquoted (`Ns.Function(...)`), even when the name has dots.
4. Fix or remove any measure with an error before refreshing; one bad measure fails the whole refresh.
5. Refresh only through `tools/run_dax.ps1 -Refresh` (TMSL, `applyRefreshPolicy: false`). Never call
   `Model.RequestRefresh` on a model with a refresh policy in Desktop.
6. Keep RLS and OLS for one audience in a single role. Test RLS with `-User`, never with your own identity
   (`USERPRINCIPALNAME()` returns `MACHINE\user` locally).
7. Do not treat perspectives as security.
8. Aggregation columns must have exactly the data type of the detail column they replace. Prove every hit and miss
   with `tools/trace_query.ps1`.
9. Edit TMDL, then `pbir desktop refresh --model`. Never press Save in Desktop. Close with `Stop-Process`.
10. Run Tabular Editor 2 against the `definition` folder, with no trailing backslash.
11. Check scaled number formats (`,,` scaling) on the report canvas, not through `FORMATTED_VALUE`.
12. Commit a VertiPaq summary only through `tools/vpax_summary.py`, never the `.vpax`.

## Notes for the tools

- Windows PowerShell 5.1 started from a PowerShell 7 or Git Bash session inherits a `PSModulePath` that breaks
  autoloading of some cmdlets (`Get-FileHash` was not found). The tools avoid those cmdlets (hashes use .NET
  directly).
- `trace_query.ps1` runs the query over ADOMD.NET (from the DAX Studio folder or the ADOMD.NET client install).
  It keeps only events from its own session, so canvas queries do not leak in. It drops the trace even on failure.
- Desktop's error and prompt dialogs are HTML windows. Their text can be read from the command line, which is how
  the dialog texts here were captured. I kept that helper in the spike and did not commit it.
