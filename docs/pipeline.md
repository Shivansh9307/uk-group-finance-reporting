# The build pipeline

One command rebuilds the database from the files in git: `ukfr build`. This page says how to run it
locally and in CI, what the options and environment variables are, how the code is laid out so that a
new source only adds files, and how the tests are organised. Every claim is labelled **tested** (with
the command and where the result is) or **designed** (not run).

## What a build does

```
uv run --project pipeline ukfr build --scope committed
```

1. Creates the database if it is missing (`--recreate` drops it first) and the eight schemas `raw`,
   `stg`, `dw`, `authored`, `synthetic`, `scale`, `quarantine`, `audit`.
2. Runs the `pre` SQL files: landing tables, safe to repeat.
3. Runs the load stages: one Python module per source reads files, checks them, and bulk-loads them
   untyped into its landing tables. Bad rows go to `quarantine`, never silently dropped.
4. Runs the `post` SQL files: every transform, in `sql/`, as T-SQL.
5. Writes every table in schema `audit` to `evidence/build/<table>.csv`.

Python fetches, parses, normalises and loads. It decides nothing about the numbers; every business
transform is a file under `sql/` (see [sql/README.md](../sql/README.md)). Amounts are `DECIMAL`,
never `FLOAT`: **tested**, `sql/tests/014_amount_types.sql` fails if any column in the database is
`float` or `real`.

## Run it locally

Needs a SQL Server instance you can create databases on. On the development machine that is the
default instance `localhost` with Windows authentication, and nothing else has to be set:

```
uv run --project pipeline ukfr fetch --verify              # every committed file matches its sha256
uv run --project pipeline ukfr build --scope committed     # build
uv run --project pipeline pytest                           # all tests
```

Use a scratch database while developing, so that a rebuild cannot touch another branch's work:

```
set UKFR_SQL_DATABASE=UKGroupFinance_scratch     (PowerShell: $env:UKFR_SQL_DATABASE = '...')
uv run --project pipeline ukfr build --scope committed --recreate
```

`--recreate` on the default database name `UKGroupFinance` also needs `--yes`.

### Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `UKFR_SQL_SERVER` | `localhost` | server, or `host,port` |
| `UKFR_SQL_DATABASE` | `UKGroupFinance` | the database the build creates and fills, and the tests read |
| `UKFR_SQL_USER` | empty | empty = Windows integrated authentication; set = SQL authentication |
| `UKFR_SQL_PASSWORD` | empty | password for the SQL login; never printed (not in logs, `repr` or error text) |
| `UKFR_SQL_ENCRYPT` | `yes` | `yes` or `no` |
| `UKFR_SQL_TRUST_SERVER_CERT` | `yes` | accept a self-signed server certificate (local and container servers) |
| `UKFR_SQL_LOADER` | `bulk` | `bulk` = the driver's bulk copy; `executemany` = plain parameter arrays, slower |
| `UKFR_DATA_DIR` | `<repo>/data/raw` | where files that are not in git live (scope `full`) |
| `UKFR_REQUIRE_DB` | unset | `1` makes a database test that cannot run fail instead of skipping (CI sets it) |

### Options of `ukfr build`

| Option | Meaning |
|---|---|
| `--scope committed` (default) | only sources that are in git; what CI runs |
| `--scope full` | also the stages that read files under `UKFR_DATA_DIR` (the annual restated files, the PSS database, the OSCAR Plans), and the SQL files that declare `-- scope: full` |
| `--stage NAME` (repeatable) | run only these load stages (the `pre` SQL still runs, the `post` SQL runs unless `--skip-sql`) |
| `--skip-sql` | stop after the load stages |
| `--recreate` | drop the database first, so the build starts from nothing |
| `--audit-dir DIR` | where the audit CSVs go (default `evidence/build`) |
| `--wait SECONDS` | retry the first login that long (a container is slow to accept one) |
| `--list-stages` | print the stages and their scope |

## Drivers and authentication

The loader uses `mssql-python` (Microsoft's driver, which ships its own ODBC layer and so needs no
system ODBC driver on Linux). `pyodbc` was kept as a fallback and was not needed.

| Combination | Result |
|---|---|
| Windows 11, SQL Server 2022 Developer on `localhost`, Windows integrated authentication (NTLM) | **tested**: connect, DDL, bulk copy and `executemany` all work; the full build and test suite pass. Connection reports `auth_scheme = NTLM`, `encrypt_option = TRUE` |
| Windows, `Encrypt=yes` without `TrustServerCertificate=yes` | **tested**: fails ("certificate chain was issued by an authority that is not trusted"). That is why the default sets `TrustServerCertificate=yes` |
| Ubuntu runner, SQL Server 2022 container, SQL authentication (`sa`) | **tested** in CI (run 44142602186, see Results): connect, DDL, bulk copy of 1.55 million rows, the full build, the database tests and a rebuild all pass |
| Windows, SQL authentication | **not tested**: the local instance is set to Windows authentication only, and changing that needs a restart from an elevated shell |

## Scopes

`--scope committed` builds from `data/committed/` only (the 31 in-year OSCAR releases). `--scope full`
adds stages that read `UKFR_DATA_DIR`. A stage declares `scope="committed"` or `scope="full"`; a SQL
file declares `-- scope: full` in its header. Asking for a `full` stage with `--scope committed` is an
error that names the stage. Tests that need those files use the `localdata` marker and are skipped
when the directory has no files (**tested**: `pipeline/tests/test_local_files.py` is skipped here with no
data directory and passes with `UKFR_DATA_DIR` set).

## Add a source

1. Write `pipeline/src/ukfr/stages/<source>.py` with one `STAGE = Stage(name=..., scope=..., run=...)`.
   `run(ctx)` receives the repo root, an open database connection and a log function, loads its files
   into its own landing tables and returns a dict of row counts. Nothing else lists it:
   `ukfr.stages.all_stages()` finds every module in the package (**tested**:
   `pipeline/tests/test_stage_oscar_inyear.py`, registry test).
2. Add the landing tables as `sql/raw/<NNN>_<source>.sql` (and `sql/quarantine/<NNN>_<source>.sql`),
   `IF OBJECT_ID(...) IS NULL CREATE TABLE ...`. Pick `NNN` inside your task's reserved range.
3. Add the transforms as `sql/stg/...`, `sql/dw/...` and so on, one object per file.
4. Add invariants as `sql/tests/<NNN>_<name>.sql`, each returning the offending rows.
5. If a table in schema `audit` should be written out at the end of every build, create it in a `post`
   file under `sql/audit/`; the export picks up every table in that schema.

Load through `ctx.db.insert_many(table, columns, rows)`, which uses bulk copy by default and
`executemany` when `UKFR_SQL_LOADER=executemany`. Bulk copy checks string lengths on the client and
fails the whole call on a value that does not fit, so size landing columns for the data.

## How the tests are organised

All tests run with `uv run --project pipeline pytest`.

| Kind | Where | Marker |
|---|---|---|
| Plain unit tests: SQL file discovery and batch splitting, settings, stage registry, row classification, exactness helpers | `pipeline/tests/test_sqlrunner.py`, `test_db_settings.py`, `test_stage_oscar_inyear.py` | none; run without a database |
| Data invariants, one `.sql` file each returning offending rows (zero rows passes), collected by scanning the folder | `sql/tests/*.sql`, run by `pipeline/tests/test_sql_invariants.py` | `db` |
| Database behaviour that needs Python: quarantine with planted bad rows (both loaders), the exact-sum SQL function, audit export determinism, independent control against loaded data | `test_stage_oscar_inyear.py`, `test_audit_output.py`, `test_independent_control.py` | `db` |
| Checks that need files outside git | `test_local_files.py`, and any SQL test with `-- marker: localdata` | `localdata` |

The `db` tests read a database that `ukfr build` has already filled; they do not build one. With no
reachable server, or an unbuilt database, they are skipped, unless `UKFR_REQUIRE_DB=1` makes that a
failure. `pytest -m "not db"` runs only the database-free tests.

The in-year invariants (**tested**, all in `sql/tests/`, run for all 31 releases): every release has
exactly one primary file; raw rows equal the file's `data_rows` and raw rows + quarantined rows equal
rows read; the raw exact sum equals `amount_sum`; the staged sum equals `amount_sum_rounded_4dp`;
staged rows equal `data_rows` - `zero_rows`; the grain is unique; periods and financial years match
each release's expected window; the twin is proven identical and not loaded; no real row is
quarantined; file hashes match the manifest; period 0 exists only in June 2019; the quarter is derived
from the month; staged rows trace to raw rows; `audit.file_control` passes for every file.

The independent control (`ukfr control inyear`, `data/audit/inyear_independent_control.csv`) is
described in [data-dictionary/inyear-raw.md](data-dictionary/inyear-raw.md). The organisation and department dimensions and the authored CSV loader are in [data-dictionary/organisation.md](data-dictionary/organisation.md). The annual restated (BUD) workbooks and the PSS database, loaded only with `--scope full`, are in
[data-dictionary/annual-restated.md](data-dictionary/annual-restated.md). The in-year conformed dimensions and the revision-delta fact are in
[data-dictionary/outturn.md](data-dictionary/outturn.md). The departments' monthly forecast returns, my own forecast and the accuracy tables are in [data-dictionary/forecast-returns.md](data-dictionary/forecast-returns.md). The spending plans (Estimates, PESA, OSCAR Plans) are in [data-dictionary/plans.md](data-dictionary/plans.md). The map from every in-year line to its department in the current structure, the authored review of the BEIS split and the hold-out against the 2025 annual file are in [data-dictionary/current-structure.md](data-dictionary/current-structure.md). The outturn-to-group bridge, the phasing of the plans and outturn on the plan's basis are in [data-dictionary/plan-phasing.md](data-dictionary/plan-phasing.md). The one synthetic table, the invented user map that drives the security roles, is loaded by its own stage from `synthetic/user_department.csv` and described in [security.md](security.md).

## Continuous integration

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`. The job `pipeline-sql`
(Ubuntu runner, SQL Server 2022 container started with `docker run`, SQL authentication) is the one that proves
the pipeline. Its steps, in order, with what each asserts:

| Step | What it does | Fails when |
|---|---|---|
| Start SQL Server container | pulls the image and starts the container | the image cannot be pulled |
| Restore, prune and save the uv cache | `actions/cache/restore` and `actions/cache/save` as separate steps (the save runs after a failed job too), key = uv version and `pipeline/uv.lock`; all actions pinned by commit SHA | never (a cache miss is a miss) |
| Install uv and the project | `uv sync --frozen` | the lock file and `pyproject.toml` disagree |
| Committed files, unit tests, assertion inventory | `ukfr fetch --verify`, `pytest -m "not db"`, `ukfr inventory` | a committed file does not match its sha256; a test fails; a file in `sql/tests` has no `-- test:` header; `docs/reconciliation.md` is out of date |
| Build | `ukfr build --scope committed` | any SQL batch or load fails |
| Database tests | `pytest -m db` with `UKFR_REQUIRE_DB=1` | any assertion fails, or a database test cannot run |
| Recompute the committed-scope expected values | `ukfr expected --out-dir <temp> --skip-unavailable` against the database just built, then `diff -r` with `tests/expected_committed` | an expected-value query no longer runs or gives other numbers on the committed data, or the committed set was edited by hand ([evidence.md](evidence.md)) |
| Rebuild and compare | a second build into a second database, then `diff -r` of the audit output against the first build and `git diff --exit-code` against `evidence/build` | the audit output is not identical, or differs from the committed copy |
| Negative control | `ukfr negative-control` in the second database: plants a wrong control total, a wrong raw amount and a wrong fact amount, requires the controls to fail, restores, requires them to pass, then checks that no file changed | a planted error is not caught, a restore is not clean, or a file changed |
| Summary | prints the seconds of every step and the test results to the job summary | never |

Every step that matters prints its seconds (`<step>_s=<seconds>`, from `.github/scripts/step-timer.sh`), and the
Summary step lists them with the test totals. The `evidence-ledger` job runs `ukfr ledger check` on a bare Python (standard library only) and fails when the model, a DAX test,
an expected value, a result or the model reference no longer matches `evidence/ledger.json` ([evidence.md](evidence.md)). The `model-bpa` job runs Tabular Editor 2's Best Practice Analyzer on the real model
(`model/UKGroupFinance.SemanticModel/definition`, with the rule file `te/bpa/rules.json`, see [te/bpa/README.md](../te/bpa/README.md))
and compares the counts of the run with `evidence/bpa`; the
`report-checks` job runs the rules of `tests/report` on the real report (`model/UKGroupFinance.Report`). The DAX tests
of the model run on my machine against Desktop and are described in [model-testing.md](model-testing.md).

**Tested** (GitHub Actions, job `pipeline-sql`, seconds per step as the job printed them):

| Step | Run 1, cold cache ([44256921066](https://github.com/Shivansh9307/uk-group-finance-reporting/actions/runs/44256921066)) | Run 2, uv cache hit ([44258121672](https://github.com/Shivansh9307/uk-group-finance-reporting/actions/runs/44258121672)) |
|---|---:|---:|
| container image pull | 6.0 | 6.7 |
| `uv sync` | 0.7 | 0.4 |
| `ukfr fetch --verify` | 0.4 | 0.2 |
| unit tests (no database) | 13.3 (182 passed, 2 skipped) | 7.0 (182 passed, 2 skipped) |
| assertion inventory | 0.3 | 0.2 |
| committed-scope build | 213.6 (stage `oscar_inyear` 88.4, post SQL 122.9) | 109.1 |
| database tests | 28.3 (129 passed, 28 skipped) | 14.4 (129 passed, 28 skipped) |
| rebuild and compare | 216.0 | 109.0 |
| negative control | 15.2 | 7.3 |
| whole job | 8 min 30 s | 4 min 32 s |

The 28 skips in the database tests are the assertions whose scope is full: the committed-scope database has no
table for them. Run 1 missed the uv cache and saved it; run 2 hit it. The cache saved little (`uv sync` takes under a
second either way); the difference between the two runs is mostly the speed of the runner, which halved the build
times with no change to the code. Run 1 is the green run in which every planted error was caught
(`caught` for tests 003, 004, 302 and `test_real_totals`, and `after the restore: pytest exit code 0 (clean)` for each
plant). Run 2 is the same code with the raw sum control deliberately blinded in a temporary commit (a `WHERE 1 = 0`
added to `sql/tests/003`, reverted afterwards): its database tests stay green, because the blinded test passes,
and the negative control step goes red with `NOT CAUGHT: ...test_invariant[003_raw_exact_sum_equals_file_sum.sql]`
and the job fails. That is how a broken control looks.

### The assertion inventory and the evidence it needs

`ukfr inventory` lists every SQL assertion with its scope and marker and every Python test that reads the database;
`ukfr inventory --write` rewrites the generated block of [reconciliation.md](reconciliation.md). **Tested**:
`pipeline/tests/test_inventory.py` fails if a SQL test has no header, if two tests share an id, or if the block is
out of date. `ukfr real-totals` prints the row count and sum of each real fact and, with `--write`, updates
`evidence/expected/real_fact_totals.csv` for the scope of the database; `pipeline/tests/test_real_totals.py` compares
every build with that file. `ukfr build-summary` turns a full build log and a test run into the small files under
`evidence/full/` (`build_summary.csv`, `pytest_summary.csv`, `table_counts.csv`); it refuses a log with a local path
or a user name, and a test run with a skip or a failure.

## Determinism

Everything a build writes is free of timestamps and ordered by primary key, amounts are exact text and
files have LF line ends (`.gitattributes` pins `evidence/build/*.csv`).

- **Tested**: two builds from an empty database, in separate runs, wrote byte-identical audit files
  (`diff -r` and sha256 of each file, see Results).
- **Tested**: `pipeline/tests/test_audit_output.py` exports twice and compares the bytes, and compares
  the export with the copy committed under `evidence/build`.

## Results

Local runs on 17 November 2026 (Windows 11, SQL Server 2022 Developer, `localhost`, Windows
authentication, a scratch database), **tested**:

| Command | Result |
|---|---|
| `ukfr build --scope committed --recreate`, twice, separate runs | both succeed; stage `oscar_inyear` 89.5 s and 89.8 s, derived SQL 17.8 s and 16.1 s, 1 min 48.6 s and 1 min 46.9 s in total |
| `diff -r` of the two audit directories | identical; sha256 `82f565b4...a44b` for `file_control.csv`, `0d627116...570f` for `table_counts.csv`; both equal the copies under `evidence/build` |
| `ukfr build --stage oscar_inyear` on the existing database (no `--recreate`) | succeeds in 1 min 45 s and rewrites the same audit files |
| `pytest` | 178 passed, 1 skipped (the `localdata` test, no data directory); 19 s |
| `pytest` with `UKFR_DATA_DIR` set, `test_local_files.py` only | 1 passed |
| `ukfr fetch --verify` | 32 committed files ok, 0 failures |

Row counts after a build (`evidence/build/table_counts.csv`): `raw.oscar_inyear` 1,547,078;
`raw.oscar_inyear_file` 32; `raw.oscar_inyear_control_expected` 32; `quarantine.oscar_inyear` 0;
`stg.inyear_snapshot` 1,328,986; `stg.release` 31.

CI, run [44142602186](https://github.com/Shivansh9307/uk-group-finance-reporting/actions/runs/44142602186)
on commit 6269a2b, job `pipeline-sql` (Ubuntu runner, SQL Server 2022 container, SQL authentication as
`sa`), **tested**: 3 min 0 s wall clock from start to finish. Of that: container image pull 7.0 s;
`uv sync` 4.6 s; database-free tests 7.7 s (142 passed, 1 skipped); first build 67.4 s (stage 55.0 s,
derived SQL 12.0 s); database tests 4.0 s (36 passed); rebuild into a second database 67.5 s, with
`diff -r` against the first audit output and `git diff --exit-code` against the committed copy both
clean. The load dominates: the stage that reads and bulk-loads 1.55 million rows is about 80% of each
build, and the two builds are about 75% of the job.

A second run on the same code plus this page (run
[44144047525](https://github.com/Shivansh9307/uk-group-finance-reporting/actions/runs/44144047525)) took
5 min 0 s: the two builds took 130.6 s and 130.2 s (stage 109.7 s and 108.8 s, derived SQL 20.4 s and
21.0 s), the database tests 5.4 s. So the runner's speed varied by about a factor of two between the
two runs; the job stayed well under the ten minutes I would treat as too slow.
