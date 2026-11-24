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
the committed results were produced by the current model. What it can do is make them tamper-evident: `evidence/ledger.json` holds
a hash of the model's TMDL and the sha256 of every test, expected value and result, and `ukfr ledger check` fails in CI when any of
them no longer matches. That is a ledger, not a rerun of DAX, and what it proves and does not prove is in [evidence.md](evidence.md)
(**tested**: `pipeline/tests/test_ledger.py`).

## The layout

| Path | What it is | Written by |
|---|---|---|
| `tests/dax/<NNN>_<name>.dax` | one `EVALUATE` query against the model, with explicit column names | me |
| `tests/expected/<NNN>_<name>.sql` | a query over `dw` base tables that returns the same columns | me |
| `tests/expected/<NNN>_<name>.py` | instead of the `.sql`, where the truth is a published file and not a warehouse table (tests 703 to 705): `generate(root)` returns the columns and rows. A module whose function is `generate(root, db)` is also given the database connection, for a truth that mixes a warehouse query with a file (tests 770 to 776, which deflate warehouse amounts with the pinned index) | me |
| `tests/expected/<NNN>_<name>.csv` | the expected values | `ukfr expected` |
| `tests/expected/_meta.csv` | the build scope (`committed` or `full`) the expected values came from | `ukfr expected` |
| `tests/expected_committed/` | a second set of expected values, written at committed scope from a database built from the files in git, with `_meta.csv` and `_skipped.csv` (the tests left out and why). CI regenerates it in the container and requires it to be identical | `ukfr expected --out-dir tests/expected_committed --skip-unavailable` |
| `evidence/ledger.json` | the model hash and the sha256 of every file above, of the role cases and of the model reference | `ukfr ledger write` |
| `tests/results/<NNN>_<name>.csv` | what the model returned | `tools/run_dax_tests.ps1` |
| `evidence/model/dax_tests.csv` | test id, name, rows, columns, status, largest absolute difference, build scope | `ukfr dax-compare` |

Test numbers 700 to 719 belong to the model skeleton, 720 to 739 to the measures, 740 to 759 to the income and
expenditure statement, 760 to 769 to the restatement and current-structure measures and 770 to 779 to real terms and
perspectives, 810 to 819 to the equality of the rewritten slow measures with their plain forms and 820 to 829 to the two hidden security tables, and 150 to 199 to the NHS trust accounts; later model tasks take their own ranges.

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

After the role cases have passed too (below), `ukfr model-docs` and `ukfr ledger write` close the run: the order of every step is in
[evidence.md](evidence.md#how-to-refresh-it).

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
3. `ukfr expected --filter <NNN>`, run the DAX, `ukfr dax-compare`. An expected query may start with statements that build temporary tables (the pay bridge tests do, to keep every join an equality; the runner skips the statements that return no rows and reads the first result set).
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

### The rewrite equality tests (810 to 813)

Four tests for the two rewritten slow measures. Each returns the plain form (the hidden measure with `(naive)` in its name) and the
rewrite side by side, with their difference, over the grids of the performance queries, and each expected file comes from T-SQL
over `dw` (a running sum over the releases for 810 to 812, `RANK()` over the year-end variance % of the DEL headline for 813). The
expected file therefore holds the same value in the plain and the rewritten column and 0 in the difference column, so the rewrite
has to equal SQL and so does the plain form.

| Test | What it proves | Rows | Expected values from |
|---|---|---:|---|
| 810 `naive_equals_rewrite_as_at_by_year` | `Outturn as at Release` (plain and rewrite) for every release and financial year | 151 | `dw.fact_outturn`, running sum |
| 811 `naive_equals_rewrite_as_at_by_department` | the same for every release and department of the current structure | 1,931 | `dw.fact_outturn`, running sum |
| 812 `naive_equals_rewrite_as_at_year_department` | the same on the 9,065-cell stress grid, summarised by release: cells, the two totals, the largest cell difference and the number of cells that differ | 31 | `dw.fact_outturn`, running sum |
| 813 `naive_equals_rewrite_rank` | `Department Group Rank (YTD Variance %)` (plain and rewrite) for the groups of 2024-25 at period 12 and for three years, on the DEL headline plan measures | 92 | T-SQL `RANK()` over `dw.outturn_plan_basis_inyear` and `dw.fact_plan` |

The performance queries (`tests/perf/`, and `tests/perf/naive/` for the plain forms) are not tests and have no expected values; `docs/performance.md` says how they are run.

### The security table tests (820 to 822)

Three tests for the two hidden synthetic tables of the security roles, described in [security.md](security.md). The expected values come from `synthetic.user_department` with the department dimension (820), from the authored group map with the plan-group rule written as "a group with a member and no member outside the user's departments" (821 and the plan-group row count in 822), and from the facts summed on their own (822).

| Test | What it proves | Rows | Expected values from |
|---|---|---:|---|
| 820 `user_department_rows` | the hidden table holds the user and department key of every row of the map | 11 | `synthetic.user_department`, `dw.dim_department` |
| 821 `user_plan_group_rows` | the hidden table holds the user and group key of every group whose departments the user holds in full | 10 | `authored.department_sr_group`, `dw.dim_sr_group` |
| 822 `unrestricted_totals_with_the_user_map_loaded` | with no role the model's totals equal the facts, and the two tables have their row counts | 8 | `dw.fact_outturn`, `dw.fact_plan`, `dw.fact_plan_phased` |

### The NHS trust accounts tests (150 to 163)

Fourteen tests for the eight TAC tables, their 16 measures and the three pages ([model.md](model.md#the-nhs-trust-accounts-balance-sheet-cash-flow-and-elimination-control)). Their expected values come from `dw` base tables (`dw.tac_fact`, `dw.tac_provider`, `dw.tac_cash_flow_derived`, `dw.tac_consolidated_control` and the dimensions) and, where the build already
audits the same thing, from `audit.tac_prior_year_summary`, `audit.tac_cash_flow_section_residual`; never from a `dw.v_model_tac_*` view. All need a full-scope database. The measures that the tests define with `DEFINE MEASURE` (the carry-forward pattern, the sum of every row, the sum of the years) are the patterns the model does **not** use, written
to show the difference.

| Test | What it proves | Rows | Expected values from |
|---|---|---:|---|
| 150 `tac_row_counts` | every TAC table has the rows of its base table (the cash-flow line view adds the member Not compared) | 8 | `dw` base tables |
| 151 `tac_relationship_integrity` | no row of the many side of the 11 relationships lacks a member | 11 | anti-joins on `dw` |
| 152 `tac_closing_balance_by_year_and_section` | `TAC Closing Balance` and the providers reporting by year and block of the balance sheet | 42 | `dw.tac_fact` |
| 153 `tac_opening_prior_closing_and_restatement` | opening, prior-year closing, their difference and the restatement by year and block | 42 | `dw.tac_fact` (prior-year column against the year before) |
| 154 `tac_restatement_equals_the_prior_year_audit` | the restatement by year and statement, all rows against `audit.tac_prior_year_summary` and lines only | 15 | `audit.tac_prior_year_summary`, `audit.tac_prior_year_difference` |
| 155 `tac_balance_over_a_span_is_the_last_year_not_the_sum` | closing, opening, sum of the years and providers for four spans | 4 | `dw.tac_fact` |
| 156 `tac_dissolved_providers_have_no_balance_after_their_last_year` | nine real predecessors x six years: the closing cash is 0 after the last year, and a carry-forward would not be | 54 | `dw.tac_fact`, `dw.tac_provider` |
| 157 `tac_group_balance_by_year_and_the_carried_forward_overstatement` | group cash per year equals SQL; the carried-forward total is larger by the balances of providers that have gone | 6 | `dw.tac_fact` |
| 158 `tac_subtotals_never_enter_a_sum` | the four balance-sheet blocks added from lines equal the published subtotals; the income statement from lines against every row | 30 | `dw.tac_fact`, `dw.tac_statutory_line` |
| 159 `tac_cash_flow_derived_published_and_residual_by_line` | derived, published and residual by year and derived line | 132 | `dw.tac_cash_flow_derived`, `dw.tac_cash_flow_comparison`, `dw.tac_fact` |
| 160 `tac_cash_flow_residual_by_section` | the same by section | 24 | `audit.tac_cash_flow_section_residual` |
| 161 `tac_net_change_in_cash_derived_published_and_balance_sheet` | the net change in cash three ways and the residual | 6 | `dw.tac_cash_flow_derived`, `dw.tac_fact` |
| 162 `tac_elimination_gap_by_year_and_control_line` | provider sum, consolidated, gap and gap % for six lines x six years | 36 | `dw.tac_fact`, `dw.tac_control_member`, `dw.tac_consolidated_control` |
| 163 `tac_derived_and_authored_amounts_stay_out_of_real_totals` | the real fact, `TAC Amount`, `Outturn`, the derived cash flow and the consolidated amounts each equal their own table | 1 | `dw` base tables |

`dax-compare`: 98 of 98 pass (84 older and 14 new), largest absolute difference of the new tests 0.00005 (test 162's ppm column), expected build scope full. The 26 role cases of the NHS trust accounts are in [security.md](security.md).

## Role cases

The cases that run under a role are not DAX tests: each needs a role and a user, which `tools/run_dax.ps1` passes with `-Roles` and `-User`. They live in `tests/rls/` (a manifest of case, query, role, user, mode and expected, the queries, the expected SQL, the results) and are run and compared by `tools/run_rls_tests.ps1`, `ukfr rls-expected` and `ukfr rls-compare`, which write `evidence/model/rls_tests.csv`. The three modes are `values` (equal to SQL), `differs` (not equal to the unfiltered total) and `error` (the engine refuses the query with a stated text). The cases, the roles and the results are in [security.md](security.md). **Tested**: `pipeline/tests/test_rls_tests.py` (the comparison and the manifest checks, without Desktop).

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

- A rerun of the DAX tests in CI. There is no engine on a hosted runner, so CI hash-checks the results and recomputes only the expected values of the committed scope ([evidence.md](evidence.md)).
- Security in the service: security groups, app audiences and the report under a role (designed, not run: [security.md](security.md)).
- Performance beyond the two slow measures and the queries of the test suite: see [performance.md](performance.md), which lists what was not run.
