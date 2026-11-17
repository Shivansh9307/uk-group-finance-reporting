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
| 400-449 | the annual restated (BUD) and PSS load, `dw.fact_outturn_annual`, their reference maps and controls (scope full) |
| 300-399, 450-599 | later tasks, each task takes its own block |

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
`db`. See [docs/pipeline.md](../docs/pipeline.md).
