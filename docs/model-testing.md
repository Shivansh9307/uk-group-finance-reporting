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
| `tests/expected/<NNN>_<name>.py` | instead of the `.sql`, where the truth is a published file and not a warehouse table (tests 703 to 705): `generate(root)` returns the columns and rows. A module whose function is `generate(root, db)` is also given the database connection, for a truth that mixes a warehouse query with a file (tests 770 to 776, which deflate warehouse amounts with the pinned index) | me |
| `tests/expected/<NNN>_<name>.csv` | the expected values | `ukfr expected` |
| `tests/expected/_meta.csv` | the build scope (`committed` or `full`) the expected values came from | `ukfr expected` |
| `tests/results/<NNN>_<name>.csv` | what the model returned | `tools/run_dax_tests.ps1` |
| `evidence/model/dax_tests.csv` | test id, name, rows, columns, status, largest absolute difference, build scope | `ukfr dax-compare` |

Test numbers 700 to 719 belong to the model skeleton, 720 to 739 to the measures, 740 to 759 to the income and
expenditure statement, 760 to 769 to the restatement and current-structure measures and 770 to 779 to real terms and
perspectives; later model tasks take their own ranges.

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

### The measure tests (720 to 737)

Each compares a DAX query on the measures with a query over `dw` base tables (or, for 732, a rule written in Python).
Percentages are multiplied by one million in both queries so the 0.0001 tolerance is tight. 723, 729 and 731 to 734 and
737 need the OSCAR Plans (grain A) and so a full-scope database; `sql/tests/720` pins the four sign cells and carries the
`localdata` marker.

| Test | What it proves | Expected values from |
|---|---|---|
| 720 `outturn_by_year_department` | `Outturn` by financial year x current-structure department (537 cells) | `dw.fact_outturn` |
| 721 `outturn_by_year_release` | `Outturn` by year x release (31 cells): the delta each release made | `dw.fact_outturn` |
| 722 `plan_by_year_group_source` | `Plan` by year x Spending Review group x plan source (387 cells) | `dw.fact_plan` |
| 723 `plan_grain_guard` | the number of non-blank `Plan` cells at 13 levels in a grain A year and a grain B/D year: 0 below the grain, the number of keys at it | `dw.fact_plan`, the dimensions |
| 724 `plan_phased_year_equals_plan` | `Plan (phased)` over a year equals `Plan`, by group (270 cells); FY2017-18 has no phased plan | `dw.fact_plan`, `dw.fact_plan_phased` |
| 725 `plan_phased_by_month` | `Plan (phased)` by year x period (132 cells) and `Plan` BLANK in all | `dw.fact_plan_phased` |
| 726 `outturn_plan_basis_by_group_measure` | `Outturn (plan basis)` for the seven defined plan measures by year x group (844 cells) | `dw.outturn_plan_basis_inyear` |
| 727 `time_intelligence_by_year` | the eight time items at year grain, three years x two departments (42 cells) | T-SQL window functions over a period grid |
| 728 `time_intelligence_by_month` | the same at month grain, periods 0 to 12 (504 cells), the rolling window crossing the year | T-SQL window functions over a period grid |
| 729 `sign_cases` | the four sign cases: Actual, Plan, Variance, Variance %, indicator for four real cells | `dw.fact_plan`, `dw.fact_outturn` |
| 730 `calculation_group_combinations` | all 40 time x comparison combinations of one cell, 16 of them BLANK on purpose | `dw.fact_plan`, `dw.fact_outturn` |
| 731 `display_unit_values` | the comparison items under the three units | `dw.fact_plan`, `dw.fact_outturn` |
| 732 `format_strings` | what `Format.ForUnit` returns for 40 combinations x 3 units | the rule, in Python |
| 733 `phased_plan_never_reaches_outturn_or_plan` | the totals of `Outturn`, `Plan` and `Plan (phased)` equal their own facts; BLANK under the scenario `Plan (phased)` | `dw.fact_outturn`, `dw.fact_plan`, `dw.fact_plan_phased` |
| 734 `plan_grain_a_by_organisation` | `Plan` by organisation code x control budget detail x economic budget, 2019-20 (881 cells) | `dw.fact_plan` |
| 735 `outturn_plan_basis_other_measures` | `Outturn (plan basis)` for NON_DEPT_AME, NON_BUDGET, UNCLASSIFIED (69 cells) | `dw.fact_outturn` and its dimensions |
| 736 `outturn_plan_basis_default_measures` | with no measure chosen, the basis adds the measures present and leaves administration out (88 cells) | `dw.outturn_plan_basis_inyear` |
| 737 `display_unit_with_time_intelligence` | the time items under the three units | `dw.fact_outturn` |

`tools/run_mdx.ps1` and `tests/mdx/format_strings.mdx` are not a DAX test: they ask the engine for the formatted value of
100 cells and write [evidence/model/format_strings.csv](../evidence/model/format_strings.csv), which is how the format
string expressions are shown to be in force (the file has no expected values; I read it).

### The statement tests (740 to 752)

Thirteen tests for the group income and expenditure statement. Their expected values come from `dw.v_statement_pnl` (the
statement computed in SQL), from the fact through the statement tables, or from T-SQL window functions; the table is in
[model.md](model.md#the-group-income-and-expenditure-statement). They need a full-scope database for the plan cells (the OSCAR
Plans years). 750 has a Python expected source because the field parameter is a definition, not warehouse data.
Counts of the engine's result: 740 329 rows, 741 9, 742 34, 743 384, 744 72, 745 33, 746 40, 747 50, 748 74, 749 171,
750 4, 751 8, 752 39.

### The restatement and current-structure tests (760 to 769)

Ten tests for the measures in the display folders `Restatement` and `Current Structure` and the rank by year-to-date
variance %. I ran them against a full-scope database and not against a committed-scope one (the expected values of 768 read
the plans of 2023-24 to 2025-26, which both scopes hold, but I did not compare). Expected values come from `audit.file_control`, from T-SQL window
functions over a grid of every release, from `dw.dq_issue` with the fact, and from `dw.current_structure_line`; the table is
in [model.md](model.md#restatement-how-a-figure-changed-from-release-to-release). Every query ends in a full `ORDER BY`.

| Test | What it proves | Rows | Expected values from |
|---|---|---:|---|
| 760 `as_at_release_equals_file_total` | `Outturn as at Release` at each of the 31 releases, on its own year, equals the file total | 31 | `audit.file_control` |
| 761 `as_at_release_by_department` | the same by department of the current structure at four releases | 237 | `dw.fact_outturn` |
| 762 `revisions_by_release_department` | as at, first reported, revision, `Revision %`, in release, restatement and the two gross forms, six releases by department | 356 | T-SQL window functions |
| 763 `data_quality_exclusion_by_release` | the exclusion removes exactly the thirteen flagged rows' amounts, in all 31 releases; the gross measures without the whole pair | 31 | `dw.dq_issue`, `dw.fact_outturn` |
| 764 `structure_totals_by_year` | the total, the sums over departments of the current and as-reported structures and of the transfer, per year | 9 | `dw.fact_outturn`, the three mapping rules |
| 765 `structure_totals_by_release` | the same per release | 31 | the same |
| 766 `structure_by_department_year` | current structure, as reported and transfer by department and year | 537 | `dw.current_structure_line`, the three mapping rules |
| 767 `estimated_mapping_share` | the estimated amount and its share by department and year | 530 | `dw.current_structure_line` |
| 768 `rank_by_ytd_variance_percent` | the year-to-date variance % and its rank by group, three years | 69 | T-SQL `RANK()` over `dw.outturn_plan_basis_inyear` and `dw.fact_plan` |
| 769 `restatement_under_time_and_unit` | five measures under Current, YTD, PY, YoY and three units, two releases | 24 | the fact, windows written in T-SQL |

### The real-terms and perspective tests (770 to 777)

Eight tests; the table and the three-year result are in [model.md](model.md#real-terms). Expected values come from
`tests/expected/77x_*.py`, which read amounts from `dw` through SQL and the deflator index from the pinned October 2026 Budget
workbook through `ukfr.readers.deflators`, and multiply them as Decimals. 770 to 776 are real terms (7, 12, 17, 537, 9, 15 and 4 rows,
largest differences between 0 and 0.00005, the four-decimal rounding of a fixed decimal result). 777 compares the measures that
the engine lists for each perspective with `te/scripts/perspectives.csv` (42 rows). They need a full-scope database for the plan
cells of 771 and 773. All 55 tests, the 47 older ones among them, passed in one run
(`dax-compare: 55 of 55 pass`), and the 47 older result files were byte for byte unchanged.

The performance queries (`tests/perf/`) are not tests and have no expected values; `docs/performance.md` says how they are run.

## The Best Practice Analyzer count check

The DAX tests need Desktop, so CI cannot run them. What CI does run on the model is Tabular Editor 2's analyzer with
`te/bpa/rules.json` (job `model-bpa`, severity 3 fails the job) and then `python tools/summarise_bpa.py --trx <result> --check
evidence/bpa`: the run must give exactly the rules, severities and violations in `evidence/bpa/bpa_counts.csv` and
`bpa_violations.csv`, and a rule that Tabular Editor cannot evaluate fails the job. So a new violation below severity 3, or a
rule added or changed, is a failing check until I have read it and written the files again with `--write`. **Tested** locally: the
run of the committed model matched the files (`the run matches evidence/bpa: 63 rules, 11 violations`), `pipeline/tests/test_model_scripts.py`
runs the tool on a small result file (counts, sorting, a difference exits 1, an unevaluable rule exits 2) and checks that the committed counts list
every rule of the file and none at severity 3 is violated. **Designed, not yet seen**: the new step on the hosted runner
(the job's result is in the pull request).

`tools/run_perspective_checks.ps1` is a recorded run, not a test: it writes `evidence/model/perspective_queries.csv`.

## Not covered

- A test that the model changes when a measure changes (the evidence ledger, designed, not built).
- Row-level or object-level security (designed, not built).
- Performance (designed, not built).
