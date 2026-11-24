# sql

Every business transform in the warehouse is T-SQL in this folder. Python fetches, parses, normalises
and loads; it does not decide anything about the numbers. `ukfr build` runs these files in a fixed
order that it works out from the folder layout, so adding an object means adding a file and editing
no list.

## Layout

```
sql/<layer>/<NNN>_<object_name>.sql
sql/tests/<NNN>_<what_must_hold>.sql
```

`<layer>` is a warehouse schema: `raw`, `quarantine`, `authored`, `synthetic`, `stg`, `dw`, `scale`,
`audit` (that is the run order). `NNN` is a three-digit prefix, unique within the layer. The runner
refuses a folder that is not one of those names, a file name that does not match, and a prefix used
twice in one layer.

Prefix ranges are reserved per task so that parallel branches never collide:

| Prefixes | Used by |
|---|---|
| 000-099 | the in-year raw load and the build framework |
| 200-299 | the authored loader's typed tables, the organisation and department dimensions |
| 300-399 | the in-year conformed dimensions, `dw.fact_outturn` (revision deltas), `dw.dq_issue` and their audits |
| 400-449 | the annual restated (BUD) and PSS load, `dw.fact_outturn_annual`, their reference maps and controls (scope full) |
| 500-549 | the spending plans: Estimates, PESA and OSCAR Plans, the plan name map, `dw.fact_plan` |
| 450-499 | the current-structure map (`sql/dw/290` is its one file below this range, because the outturn fact reads it), its sub-segment labels, audits, tests and the hold-out against the 2025 annual file (scope full) |
| 550-599 | the outturn to Spending Review group bridge, the phasing profile and phased plan (derived), outturn on the plan's basis (annual and in-year), and their audits |
| 600-649 | the departmental workforce files: the landing tables (`sql/raw/600`, `sql/quarantine/600`), the typed rows, the authored name map and what each row becomes (`sql/stg/599` to `602`), the measures and `dw.workforce_month`, the quarantine of rows that are not placed (`sql/dw/600` to `606`), the control and coverage audits (`sql/audit/600` to `603`) and their tests (`sql/tests/600` to `618`); all scope full; see [docs/data-dictionary/workforce.md](../docs/data-dictionary/workforce.md). The pipeline close-out checks are Python and need no SQL prefix |
| 650-699 | the departments' monthly forecast returns: landing tables, the typed cells, the organisation map, `dw.forecast_return`, the quality flags, my own forecast, the accuracy tables, their audits and tests (scope full); see [docs/data-dictionary/forecast-returns.md](../docs/data-dictionary/forecast-returns.md) |
| 700-719 | the views the semantic model reads (`dw.v_model_*`, one per model table) and their tests; see [docs/model.md](../docs/model.md) |
| 740-759 | the group income and expenditure statement: the typed layout (`stg`), the resolved lines and the account mapping (`dw`), the view the model reads for it, and the statement computed in SQL that the model's measures are tested against; see [docs/data-dictionary/statement.md](../docs/data-dictionary/statement.md) |
| 760-779 | the restatement and current-structure measures of the model: the table that maps each reported department number to the department of the current structure that answers for it, the view `dw.v_model_department` that carries the list of numbers, and the tests of both; see [docs/model.md](../docs/model.md) |
| 780-799 | the data-control views the report reads (`dw.v_model_file_control`, `v_model_plan_coverage`, and in scope full the annual, PSS and load controls) and their tests. The files sit in `sql/audit/` because the views read audit tables, which are built after `dw`; see [docs/model.md](../docs/model.md) |
| 800-819 | the plan variance reconciliation: `audit.plan_variance_reconciliation` and `audit.pesa_2026_basis_change` (scope full), the view the model reads (`dw.v_model_plan_variance`) and their tests, plus the tests of the FY2022-23 combined-group rule (`dw.plan_group_rule`, built in `sql/dw/552`) and of the annual AME basis; see [docs/reconciliation.md](../docs/reconciliation.md) |
| 820-839 | the synthetic user map and the security roles: `sql/synthetic/820` creates `synthetic.user_department` (loaded from `synthetic/user_department.csv` by the synthetic stage), `sql/dw/820` the two views the model reads for the roles (`dw.v_model_user_department`, `dw.v_model_user_plan_group`), and `sql/tests/820` to `823` their tests; see [docs/security.md](../docs/security.md) |
| 900-919 | the pay bridge (scope full): the views that compare each month's payroll paybill and full-time equivalent with the same month a year earlier and split the change into volume, rate, organisation mix and entry and exit (`sql/audit/900`: `dw.v_pay_cell`, `dw.v_pay_bridge_row` and the views the model reads, `dw.v_model_pay_*`; the files sit in `sql/audit/` because the rule that leaves out a published row whose total is not its components reads `audit.workforce_row_arithmetic`), the audit tables of the cells and rows left out and the tie per department and month (`sql/audit/905`), and their tests (`sql/tests/900` to `904`); see [docs/data-dictionary/workforce.md](../docs/data-dictionary/workforce.md) |
| 100-149 | the NHS trust accounts (TAC): landing tables, staging, the provider, line and fact tables, the file controls and the audit tables, and their tests (scope full); see [docs/data-dictionary/tac.md](../docs/data-dictionary/tac.md) |
| 150-199 | the NHS statutory statements built on the TAC tables: the typed copies of the four authored cash-flow and control files (`sql/stg/150`), the derived indirect cash flow and the published lines it is compared with (`sql/dw/150`), the elimination-gap control (`sql/dw/155`), the views the model reads (`sql/audit/150` and `151`, in the audit layer because they read `dw.tac_provider_group`), the audit tables of the cash-flow ties and residuals and of the elimination gap (`sql/audit/160` to `165`) and their tests (`sql/tests/150` to `159`); all scope full; see [docs/data-dictionary/tac.md](../docs/data-dictionary/tac.md) |

## Phases

A build has two SQL phases with the load stages in between:

1. `pre`: landing tables that a load stage writes to. Default for `raw` and `quarantine`. These files
   run on every build, so they must be safe to repeat: `IF OBJECT_ID(...) IS NULL CREATE TABLE ...`.
   A change to a landing table's shape needs `ukfr build --recreate`.
2. load stages (Python, one module per source in `pipeline/src/ukfr/stages/`).
3. `post`: everything derived from the loaded data. Default for every other layer. Each file rebuilds
   what it owns (`DROP TABLE IF EXISTS`, then create and fill), so running the build again gives the
   same result.

A comment near the top of a file overrides the defaults:

```sql
-- phase: pre          -- or post
-- scope: full         -- needs files that are not in git; skipped by `--scope committed`
```

Within a phase the order is layer, then prefix. A `post` file in `stg` can therefore read anything a
`raw` file or a load stage produced, and an `audit` file can read everything.

## Batches and errors

A line holding only `GO` (an optional count is ignored) ends a batch, the way `sqlcmd` reads it. The
runner sends each batch to the server on its own. A failing batch stops the build with the file name,
the batch number, the line the batch starts on and the server's message. Do not put `GO` inside a
string or a block comment; the split is by line.

## Rules for the SQL

- Amounts are `DECIMAL`, never `FLOAT`. OSCAR amounts are GBP thousands, spending positive, income
  negative. A test fails the build if any column anywhere is `float` or `real`.
- Real data only in real totals. Anything authored or synthetic lives in `authored`, `synthetic` or
  `scale`, is labelled in the table description and the README register, and has a test that it never
  reaches a real total.
- Nothing is dropped silently. A row the load rejects goes to `quarantine` with a reason.

## Audit output

Every table in schema `audit` is written to `evidence/build/<table>.csv` at the end of a build:
sorted by primary key, UTF-8, LF line ends, exact amounts as plain text, no timestamps. Two builds of
the same inputs write identical files, and CI compares the second build with the first and with the
committed copy.

## Tests

`sql/tests/` holds invariants. Each file is one query that returns the rows that break the invariant,
so zero rows is a pass:

```sql
-- test: <what must hold, in one sentence>
-- marker: localdata        (optional: needs files that are not in git)
SELECT ... FROM ... WHERE <violation>;
```

A test is one batch (no `GO`). The build never runs them; `pytest` does, through
`pipeline/tests/test_sql_invariants.py`, which collects every `.sql` file in the folder and marks it
`db`. A file without a `-- test:` header fails (`ukfr inventory` and `pipeline/tests/test_inventory.py` check
it), and the list of every test with its scope, marker and evidence file is generated into
[docs/reconciliation.md](../docs/reconciliation.md).
