# The evidence ledger

The DAX tests and the role cases run in Power BI Desktop against the model on my machine. A hosted CI runner has no
Analysis Services engine, so CI cannot run them again. Before this page existed, nothing stopped a stale result file, a
hand-edited expected file or a measure changed after the last run from passing CI. This page says what I did about
that, what CI now checks, and, as plainly as I can, what it still cannot prove. Every claim is labelled **tested** (with the
command and the result) or **designed**.

## What it is

`evidence/ledger.json` is a ledger, not a rerun. It records, for one state of the repository:

- a **model projection hash**: a sha256 of the model's TMDL files with everything Desktop and Tabular Editor rewrite on
  every save taken out (lineage tags, change markers, tool annotations such as `PBI_*`, the order of objects and of
  properties, the generated name of a relationship, line endings) and everything that means something kept (names,
  expressions, data types, relationships, roles and their filters, descriptions, format strings, display folders,
  calculation items with their ordinals, perspectives, the Best Practice Analyzer ignore annotations);
- the **sha256 of every file of the test evidence**: `tests/dax/*.dax`, `tests/expected/*` (the `.sql` and `.py` sources
  and the CSVs), `tests/results/*.csv`, everything under `tests/rls/` (manifest, queries, expected SQL, expected CSVs,
  results), the committed-scope set `tests/expected_committed/*`, the two comparison files
  `evidence/model/dax_tests.csv` and `rls_tests.csv`, and the model reference's queries and CSVs. Line endings are
  normalised before hashing, because `autocrlf` is on;
- the **build scope** of each set of expected values (`full` for `tests/expected`, `committed` for
  `tests/expected_committed`);
- the **model reference**: the hash of `docs/model-reference.md` and the model projection hash that page says it was
  generated from.

A matching ledger means: the model, the queries, the expected values and the results in the repository are the ones that
were compared and passed together when I wrote the ledger. Nothing more.

## What writes it, and when

`ukfr ledger write` refuses to write unless, on the files on disk, the DAX comparison passes for every test, the role-case
comparison passes for every case, the expected values are full scope, and the model reference was generated from the
model as it is now. So the ledger exists only for a model whose evidence agrees with itself (**tested**:
`pipeline/tests/test_ledger.py`, the `test_write_refuses_*` cases).

It cannot know that the result files were produced by Desktop from this model. That is my discipline, written as the order
below: results come from a Desktop that has just loaded the model on disk and refreshed it, and the ledger is written
straight after. If I edited a result file by hand and ran `ukfr ledger write`, the ledger would accept it as long as it
equals the expected value. A hosted runner cannot tell the difference.

The ledger in `evidence/ledger.json` holds 993 files: 128 DAX tests, 128 results, 128 expected sources and 129 expected value files (128 and
`_meta.csv`), 70 files of the committed-scope set, 29 role-case queries, 23 expected sources and 162 expected value files for them, 173 role-case
results, the role-case manifest, 2 comparison files and 20 files of the model reference (10 queries, 10 CSVs). The expected values were written at
`full` scope and the committed set at `committed`. **Tested**: `ukfr ledger check` on 2026-11-25 printed
`ledger: ok, 993 files, model projection 5dbb9219c546, reference 5dbb9219c546`; the 128 and 173 are the rows of `evidence/model/dax_tests.csv` and
`evidence/model/rls_tests.csv`, every one with status `pass`.

## What CI checks

| Check | Where | What it catches | Status |
|---|---|---|---|
| `ukfr ledger check` | job `evidence-ledger` (Ubuntu, standard library only) | a changed, missing or extra file under the tracked folders; a model whose projection hash differs from the ledger's; a `model-reference.md` generated from another model ("model-reference.md is stale: regenerate in Desktop"); a different build scope; and, on the files as they are, the two comparisons (results against expected values) no longer passing | **tested**: the red and green runs below, `pipeline/tests/test_ledger.py` |
| the committed-scope expected values are regenerated | job `pipeline-sql`, after the container build | the expected-value queries (`tests/expected/*.sql`) no longer running, or giving other numbers, on the data in git; a change to `tests/expected_committed` that the queries do not reproduce | **tested**: the same runs |
| the model's Best Practice Analyzer counts | job `model-bpa` | unchanged by this work | tested earlier ([model-testing.md](model-testing.md)) |

What CI recomputes: the committed-scope expected values, by running their SQL (and the Python sources that need no
unpublished file) in a SQL Server container built from the files in git. The committed set is
`tests/expected_committed/`, with `_meta.csv` (scope `committed`) and `_skipped.csv`, which lists every test left out and
why: a test whose `-- requires:` table only a full build writes, and a test whose expected source reads a file that is
not in git (the deflator and CPI workbooks under `data/raw`).

What CI only hash-checks: the full-scope expected values (`tests/expected/*.csv`), the DAX results
(`tests/results/*.csv`), the role-case expected values and results, and the model reference. A hosted runner cannot build
the full-scope database, and it has no engine to run DAX.

## What it does not prove

- That a result file came from running the DAX against this model. It proves only that the result file is the one that
  was in the repository when the ledger was written, and that it equals the expected value then. The check that a measure
  edit without a rerun goes red is the model hash: a changed expression changes the hash, and the ledger no longer matches.
- That the full-scope expected values are right. They are the output of SQL I wrote against the full-scope database.
  CI re-derives the committed-scope set only; that shows the queries are stable, not that they are correct at full scope.
- That the model works in the Power BI service. The service is not part of this project.
- Anything the projection leaves out on purpose. A change that only reorders objects, changes a lineage tag or a
  `PBI_*` annotation, or rewrites line endings does not change the hash (**tested**), and it should not: such a change is
  what Desktop makes on its own.

## The red and the green run

On the pull request branch I pushed one commit that changed one measure's expression and nothing else, and let CI run;
then a second commit that restored it. Both commits stay in the branch history.

| Commit | What it did | CI | Run |
|---|---|---|---|
| `1ad47ed`, one measure expression changed | `File Total (4 decimals)` in `File Control.tmdl` gets `+ 0`; nothing regenerated | red: `evidence-ledger` failed, the other three jobs passed | [45289478357](https://github.com/Shivansh9307/uk-group-finance-reporting/actions/runs/45289478357) |
| `f91772c`, expression restored | the file put back as it was | green: all four jobs passed | [45291028434](https://github.com/Shivansh9307/uk-group-finance-reporting/actions/runs/45291028434) |

What the red run printed (job `evidence-ledger`, step "Ledger check"):

```
LEDGER: the model changed since the evidence was written: projection hash 3d9cc09a98fe in the ledger, 0fd5adc5a154 now. Run the DAX tests and the role cases in Desktop, regenerate the model reference, then `ukfr ledger write`
LEDGER: docs/model-reference.md is stale: it was generated from model 3d9cc09a98fe, the model is 0fd5adc5a154. Regenerate in Desktop (`ukfr model-docs`)
ledger: 2 problem(s)
```

The other three jobs passed on the red commit, because a `+ 0` on one measure breaks nothing that CI can run: the Best Practice
Analyzer, the database tests and the report rules do not see it. Only the ledger sees that the evidence no longer belongs to the
model. That is the point of the job, and also the limit of it: it says the evidence is stale, not that the measure is wrong.

## How to refresh it

After any change to the model (TMDL), the DAX tests, their expected sources or the role cases, in this order. Steps 1 to 3
need Desktop and the full-scope database `UKGroupFinance`; I run them in one sitting.

1. Open `model/UKGroupFinance.pbip` in Desktop, wait for the window title, then refresh the data:
   `powershell.exe -NoProfile -File tools\run_dax.ps1 -Refresh`.
2. Expected values and DAX results, then the comparison:
   `uv run --project pipeline ukfr expected`,
   `powershell.exe -NoProfile -File tools\run_dax_tests.ps1`,
   `uv run --project pipeline ukfr dax-compare`.
3. The role cases: `powershell.exe -NoProfile -File tools\run_rls_tests.ps1`,
   `uv run --project pipeline ukfr rls-expected`, `uv run --project pipeline ukfr rls-compare`.
4. The model reference, from the model that is open:
   `powershell.exe -NoProfile -File tools\run_dax_tests.ps1 -QueryDir tools/model_reference -OutDir evidence/model/reference`,
   then `uv run --project pipeline ukfr model-docs`. Run `ukfr model-docs` twice and compare: the page is byte-identical.
5. The committed-scope set, from a scratch database built from the files in git (never `UKGroupFinance`):
   `UKFR_SQL_DATABASE=UKGroupFinance_scratch uv run --project pipeline ukfr build --scope committed --recreate --audit-dir <a scratch folder>`,
   then with the same database name and no `UKFR_DATA_DIR`:
   `uv run --project pipeline ukfr expected --out-dir tests/expected_committed --skip-unavailable`, and drop the scratch
   database. Only needed when an expected source or the committed data changed.
6. `uv run --project pipeline ukfr ledger write`, then `uv run --project pipeline ukfr ledger check`.
7. Commit the changed files together, in one commit.

`ukfr ledger check` also runs without the package installed: `PYTHONPATH=pipeline/src python3 -m ukfr.ledger check`, which
is how the CI job and the release workflow run it.

## The release workflow

`.github/workflows/release.yml` runs on a tag that starts with `v`. It runs the ledger check on the tagged commit, zips
`model/` (without `.pbi/cache.abf` and `localSettings.json`) and `evidence/`, and attaches both to a GitHub release created
with `gh release create`, with the tag message as the notes. **Tested**: it ran once, on the tag `v1.0.0` on 2026-11-24 ([run 45298915073](https://github.com/Shivansh9307/uk-group-finance-reporting/actions/runs/45298915073),
`gh run view 45298915073`), and every step succeeded: the ledger check, reading the tag message, building the two
archives and creating the release, which holds `ukgroupfinance-pbip-v1.0.0.zip` and `ukgroupfinance-evidence-v1.0.0.zip`
(`gh release view v1.0.0`). That is the only run. I did not list the archives' contents after the run, and I have not run
the file through a workflow linter.
