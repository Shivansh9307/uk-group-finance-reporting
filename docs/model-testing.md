# Testing the model: DAX tests against the warehouse

Every measure and table in the semantic model is tested the same way: a DAX query runs against the model open in
Power BI Desktop, a SQL query (or, for the web-read deflators, the Python reader) produces the number I expect from
somewhere that shares nothing with the model, and a comparison writes a pass or a fail to a file in git. This page
says how to add a test, how to run the suite, and what "independent" means here. Every claim is labelled **tested**
(with the command and the result file) or **designed**.

DAX cannot run on a hosted runner without a service I do not use, so the DAX tests run on my machine against
Desktop. What CI can enforce is the part that does not need Desktop: the pairing of tests and expected values, the
comparison logic, the structure of the model files, and that the committed results agree with the committed expected
values (**tested**: `pipeline/tests/test_model_tests.py`, `pipeline/tests/test_model_files.py`). It cannot prove that
the committed results were produced by the current model; that is the evidence ledger, which I have designed and not built, and until
then it rests on me running the suite and committing the files together.

## The layout

| Path | What it is | Written by |
|---|---|---|
| `tests/dax/<NNN>_<name>.dax` | one `EVALUATE` query against the model, with explicit column names | me |
| `tests/expected/<NNN>_<name>.sql` | a query over `dw` base tables that returns the same columns | me |
| `tests/expected/<NNN>_<name>.py` | instead of the `.sql`, where the truth is a published file and not a warehouse table (tests 703 to 705): `generate(root)` returns the columns and rows | me |
| `tests/expected/<NNN>_<name>.csv` | the expected values | `ukfr expected` |
| `tests/expected/_meta.csv` | the build scope (`committed` or `full`) the expected values came from | `ukfr expected` |
| `tests/results/<NNN>_<name>.csv` | what the model returned | `tools/run_dax_tests.ps1` |
| `evidence/model/dax_tests.csv` | test id, name, rows, columns, status, largest absolute difference, build scope | `ukfr dax-compare` |

Test numbers 700 to 719 belong to the model skeleton; later model tasks take their own ranges.

## Run the suite

```
# 1. Desktop open on model\UKGroupFinance.pbip, window title UKGroupFinance
Start-Process model\UKGroupFinance.pbip

# 2. expected values from the warehouse (and the pinned files); needs the database and, for 703 to 705, UKFR_DATA_DIR
uv run --project pipeline ukfr expected

# 3. refresh the model and run every query (Windows PowerShell 5.1)
powershell.exe -NoProfile -File tools\run_dax_tests.ps1 -Refresh

# 4. compare; exits 1 on any mismatch or missing file
uv run --project pipeline ukfr dax-compare
```

`-Filter "700_*.dax"` runs one test. `-RefreshTable "Release,Fact Outturn"` refreshes only those tables, and
`-AllowUnloaded "Deflator,CPI"` lets queries run while the tables read over the web have not been loaded yet (both
are passed through to `tools/run_dax.ps1`). `ukfr expected --filter 702` regenerates one expected file.

## Add a test

1. Write `tests/dax/<NNN>_<name>.dax`: one `EVALUATE`, explicit column names (`SELECTCOLUMNS`, `ROW`), identifying
   columns first and measures after them. A measure the test needs is defined inside the file with `DEFINE MEASURE`;
   it is not a model measure.
2. Write `tests/expected/<NNN>_<name>.sql` over `dw` base tables with the same column names in the same order. Do not
   read a `dw.v_model_*` view, which is what the model reads (a pytest fails if you do). Cast amounts to
   `DECIMAL`; a float in an expected result is refused.
3. `ukfr expected --filter <NNN>`, run the DAX, `ukfr dax-compare`.
4. Commit the three source files, the two CSVs and `evidence/model/dax_tests.csv`.

## What "independent" means

The model reads views over the star schema (`dw.v_model_*`). A check that read the same views would repeat the
model's mistakes. So the expected side reads something else:

- counts and totals come from the base tables of `dw`, joined by the tests' own SQL (test 700 counts `dw.dim_period`,
  `dw.dq_issue` and the others, not the views);
- the release totals of test 702 do not come from `dw.fact_outturn` at all: they come from the control totals of the
  published files (`audit.file_control.amount_sum_4dp_expected`, loaded from `data/audit/inyear_file_control_totals.csv`),
  so the test says "the sum of the model's revision deltas up to each release equals what the release file says";
- the deflators and the ONS series (703 to 705) are read from the pinned local copies of the same files by the
  Python reader, after the copies are checked against the sha256 in the file manifest. The model downloads the files
  itself in Power Query, so a pass says that the file downloaded holds the values of the file in the manifest.

It does not mean that the expected value was computed by a different person: I wrote both sides. It means that they
share no table, view or code path, so a wrong join in a view or a wrong relationship in the model shows up as a
difference.

## How the comparison works

- Both sides are read as text, sorted on all columns from left to right (numbers by value, text without regard to
  case) and compared row by row, so the order of rows in the DAX result does not matter. Put identifying columns
  first, or two rows that differ in a measure could pair with the wrong partner.
- Column names must match (case-insensitively) after the brackets that `dscmd` writes are stripped.
- Numbers compare with an absolute tolerance of **0.0001**. That is the resolution of the amounts in the
  warehouse (`DECIMAL(19,4)`) and of the model's fixed-decimal columns, so it is one unit in the last place and never
  hides a difference in the data. Text, dates and booleans must match exactly, and a blank is not a zero.
- The largest absolute difference is written to `evidence/model/dax_tests.csv`, with the build scope of the expected
  values, so a reader can see that a pass is an exact pass.
- A missing result or expected file is a failure, not a skip.

**Tested.** `pipeline/tests/test_model_tests.py` checks equality in any row order, the tolerance at 0.0001 and
0.0002, a wrong number, wrong text, a missing row, different columns, blank against zero, booleans, a missing result
file and a missing expected file, and that `ukfr dax-compare` exits 1 on a wrong expected value and 0 on a right one
(`test_dax_compare_exits_non_zero_on_a_wrong_expected_value_and_zero_on_a_right_one`).

## The first tests

| Test | What it proves | Expected values from |
|---|---|---|
| 700 `row_counts` | every model table has the rows of its base table, or the documented subset (Fiscal Year: one row per year of `dw.dim_period`; Department (current structure): the live departments; Data Quality Issue: the findings plus the "No issue flagged" member) | `dw` base tables |
| 701 `relationship_integrity` | for each of the 21 relationships, no row of the many side lacks a row on the one side (no blank member) | anti-joins on `dw` base tables |
| 702 `outturn_total_by_release` | the sum of the deltas of a release's financial year up to and including each of the 31 releases equals the total that release's file reports, to four decimals | `audit.file_control` |
| 703 `deflators` | the 229 deflator rows loaded over the web (three vintages) equal the pinned workbooks, index, per cent change and chained index | Python reader |
| 704 `cpi` | the 918 monthly ONS values to September 2026 equal the pinned CSVs | Python reader |
| 705 `web_table_rows_and_quarantines` | the row counts of the four web tables, and both quarantines empty | Python reader |

The results of the last run are in `evidence/model/dax_tests.csv`.

## Not covered

- A test that the model changes when a measure changes (the evidence ledger, designed, not built).
- Row-level or object-level security (designed, not built).
- Performance (designed, not built).
