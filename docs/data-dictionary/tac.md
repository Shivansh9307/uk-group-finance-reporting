# Data dictionary: NHS trust accounts (TAC)

What `ukfr build --scope full` puts in the database from the NHS England TAC files: the statutory income
statement (SoCI), balance sheet (SoFP) and cash flow (SoCF) of every NHS trust and foundation trust, FY2019-20
to FY2024-25. The files are not in git (they sit under `$UKFR_DATA_DIR/tac/`), so the stage, the SQL and the tests
run only in a full build. Every claim is labelled **tested** (command and result file) or **designed**. What the
files look like and why I decided what I did is in [../profiling/tac.md](../profiling/tac.md).

Everything in the fact is a real published value. There is no synthetic data. Four small authored CSVs exist
(`authored/tac_line_role.csv`, `tac_code_map.csv`, `tac_name_alias.csv`, `tac_provider_successor.csv`); they label
lines, name three providers the way a data sheet does, and link providers, hold no amount, and are never part of a total (**tested**:
`sql/tests/114_tac_authored_data_never_reaches_a_total.sql`).

**Unit and sign.** Amounts are thousands of pounds (like OSCAR) but on the **TAC sign**, as published: income,
assets and inflows positive, expenses, liabilities and outflows negative, `+/-` lines either. This is not the OSCAR
convention (spending positive, income negative). `dw.tac_statutory_line.expected_sign` carries the sign the form
expects; a later task picks a presentation sign.

## What a later task reads

| Object | Grain | Key |
|---|---|---|
| `dw.tac_fact` | provider x file year x line x column (CY or PY) | (`provider_key`, `release`, `line_key`, `period_column`) |
| `dw.tac_provider` | one NHS (ODS) code | `provider_key`, `provider_code` |
| `dw.tac_provider_year` | provider x year it is listed | (`provider_key`, `release`) |
| `dw.tac_statutory_line` | one line of a statement | `line_key`, `sub_code` |
| `dw.tac_provider_group` | provider (link to the department level of the group) | `provider_key` |
| `audit.tac_year_summary` | file year x provider type | (`release`, `provider_type`) |
| `audit.tac_file_control_totals` | data file x worksheet | (`release`, `filename`, `worksheet_name`) |
| `audit.tac_sofp_balance` | provider x year x column | (`provider_key`, `release`, `period_column`) |
| `audit.tac_prior_year_summary`, `audit.tac_prior_year_difference` | year x statement; provider x year x line | see the SQL |

Other tables: `raw.tac_file` (18), `raw.tac_worksheet`, `raw.tac_value`, `raw.tac_provider_list`, `raw.tac_intro`,
`raw.tac_template_line`, `raw.tac_independent_expected`, `quarantine.tac_value`, `quarantine.tac_unmapped_row`,
`stg.tac_value`, `stg.tac_data_name`, `stg.tac_template_line`, `stg.tac_provider_year`, and the typed copies of the
authored files.

## Load: `ukfr.stages.tac` and `ukfr.readers.tac`

- The reader streams each sheet, turns numbers into exact `Decimal` (Excel's 15 significant digits), accepts the two
  header spellings the files use and stops on any other header, any non-number in the value column and any
  worksheet whose name does not start with a TAC form code (**tested**: `pipeline/tests/test_tac_reader.py`, 9 tests).
- It loads the three statements and counts every other worksheet in `raw.tac_worksheet` (`loaded = 0`).
- A row whose value is blank, has more than ten decimals or is out of range goes to `quarantine.tac_value` with
  a reason (**tested**: `pipeline/tests/test_tac.py::test_classify_rejects_what_the_landing_column_cannot_hold`). The
  real files have none.

## Dimensions

**`dw.tac_provider`**: one row per NHS code (228). Name, type (`NHS trust` or `NHS foundation trust`), region and
sector are the latest listed year's; `first/last_data_release` and `n_data_years` count years with statements.
`successor_*` is authored (see below). **`dw.tac_provider_year`** has the name, type and `list_status` of each
provider-year: `reported`, `excluded` (the file says the accounts were not adopted in time), `acquired` or
`listed_without_data`. The data sheet names a provider by text only; the join to the list is by a normalised name
key (`stg.tac_name_key`): the damaged apostrophe, `&` and spacing are normalised, case is ignored. Three provider-years
name the provider differently in the data sheet than in the list (the data has the later name); `authored/tac_name_alias.csv`
holds those three, and a test requires each to be needed (`sql/tests/115_...`).

**`dw.tac_statutory_line`**: 137 lines. The key is the sub code, unique across the three statements. Description and
`expected_sign` are from the latest illustrative form that carries the code. `section` and `line_kind` (line,
subtotal, total) are **authored** (`authored/tac_line_role.csv`, one row per line with evidence and a note): a
subtotal is computed by the form and is in the data as a value, so adding it to its components counts it twice.
`change_kind` and `change_note` come from `authored/tac_code_map.csv`: one retired code (`SOC0145`) and three
relabelled (`SCF0280`, `SCF0295`, `BAL1230`). The TAC codes did not otherwise change between 2019-20 and 2024-25
(**tested**: `sql/tests/110_tac_every_line_has_text_sign_section_and_kind.sql`: data codes equal the forms' codes),
so the cross-year code map is short by design.

**`dw.tac_provider_group`**: every provider links, at department level, to the Department of Health and Social Care
with the `department_key` that `dw.dim_department` gives it. The key is looked up by name, then checked against the
department key of the current `DOH033` organisation (**tested**: `sql/tests/113_tac_every_provider_links_to_dhsc_by_the_dimension_key.sql`).
The file that builds it is in `sql/audit/` because the department dimension is built after `sql/dw` files below 200.

**`authored.tac_provider_successor`**: 23 links from an acquired, merged or dissolved provider to its successor, each
with a fragment quoted from the source's own comment, which a test finds in the raw comments (**tested**:
`sql/tests/112_tac_successor_evidence_is_in_the_source_comment.sql`).

## `dw.tac_fact`

| Column | Meaning |
|---|---|
| `provider_key`, `line_key` | the dimensions |
| `release` | the year of the file the value is read from, `2024-25` |
| `period_column` | `CY` the file's own year, `PY` the prior-year column as published in that file |
| `reported_year` | the year the value is about: `release` for CY, the year before for PY |
| `value` | `DECIMAL(19,4)`, thousands of pounds, TAC sign |
| `file_id`, `source_row` | lineage to `raw.tac_value` and the workbook row |

The PY column of a balance sheet is the opening balance of the year. Zero values are kept (the forms are full of
them). Only the three statements are in the fact.

## Controls (all **tested**)

| Control | Where | Result |
|---|---|---|
| Rows and exact sum per file and worksheet against an independent recomputation (`ukfr control tac`, python-calamine, shares no code with the reader), then stg against per-row rounded raw, then fact against stg | `audit.tac_file_control_totals`, `sql/tests/100_tac_file_control_all_pass.sql` | exact 0 in every worksheet, see the results below |
| Reader count, raw rows, quarantine and staged rows add up | `sql/tests/101_tac_raw_rows_equal_file_rows.sql` | pass |
| Six years, one trust file, one foundation trust file, one form each, hashes match | `sql/tests/102_...` | pass |
| No row rejected or unmapped, every fact row has a provider and a line | `sql/tests/103_...` | pass |
| Grain unique | `sql/tests/104_tac_fact_grain_is_unique.sql` | pass |
| Providers: one row per code per year, status explained, aliases needed and exact | `sql/tests/105_...`, `106_...`, `115_...` | pass |
| Balance sheet balances to within GBP 1,000 | `sql/tests/107_tac_sofp_balances_and_every_pair_is_listed.sql` | pass |
| Prior year of Y against current year of Y-1 | `sql/tests/108_tac_prior_year_differences_are_listed_and_counted.sql` | pass (differences listed) |
| Python: loaded values equal the independent CSV by worksheet; the control CSV is reproduced byte for byte | `pipeline/tests/test_tac.py` (db, localdata) | pass |
| Authored data never reaches a total; the dimensions say what is authored | `sql/tests/114_...` | pass |
| Code map and successor evidence agree with the forms, the data and the source comments | `sql/tests/111_...`, `112_...` | pass |
| Every provider links to the DHSC department key | `sql/tests/113_...` | pass |

### Result of the full build (tested)

Command: `UKFR_SQL_DATABASE=<scratch database> UKFR_DATA_DIR=<folder with the raw files> uv run --project pipeline ukfr build --scope full --recreate --yes`,
green in 20 min 33 s; the TAC stage took 529 s of that (the reader parses 8.4 million sheet rows from 12 workbooks;
the 344,812 statement rows are loaded). Source of the table: `evidence/full/tac_year_summary.csv`, which comes from
`audit.tac_year_summary`.

| Year | Data files | Providers listed | With statements | Fact rows (CY + PY) | Control difference | Quarantined rows |
|---|---|---|---|---|---|---|
| 2019-20 | 2 | 226 | 225 | 59,400 | 0 | 0 |
| 2020-21 | 2 | 219 | 219 | 57,816 | 0 | 0 |
| 2021-22 | 2 | 215 | 215 | 56,760 | 0 | 0 |
| 2022-23 | 2 | 213 | 212 | 58,088 | 0 | 0 |
| 2023-24 | 2 | 211 | 206 | 56,444 | 0 | 0 |
| 2024-25 | 2 | 210 | 207 | 56,304 | 0 | 0 |
| **Total** | 12 | 1,294 provider-years, 228 providers | 1,284 provider-years | 344,812 | 0 | 0 |

The control difference is the sum of absolute differences, for the three statements, of: the loaded exact sum
against the independent sum, the DECIMAL(19,4) sum against the per-row rounded raw sum, and the fact against the
staged sum. All are exactly 0 in all 36 statement worksheets, and all 302 note worksheets match on row count
(`evidence/full/tac_file_control_totals.csv`, 338 rows, all `pass`). The unmapped-row quarantine is empty only
because of `authored/tac_name_alias.csv`: without the three aliases, 812 rows would be in it.

### Balance sheet and prior year (tested)

- `evidence/full/tac_sofp_balance.csv`: 2,568 provider-year-column pairs, 696 exact, 1,872 within £1,000, none beyond.
- `evidence/full/tac_prior_year_summary.csv`, `tac_prior_year_difference.csv`: for every provider-line that has a prior-year value in
  year Y and a current-year value in Y-1 (counts per year and statement are in the summary), 1,406 values
  differ by 1 or more (£1,000): 357 in 2020-21, 334 in 2021-22, 215 in 2022-23, 334 in 2023-24 and 166 in 2024-25.
  Net and absolute sums are in the summary; for example the balance sheet's 2023-24 prior year differs from the
  2022-23 current year by 138 values, net -£184.6m and £1,488.4m in absolute terms (thousands in the file). These
  are restatements, reclassifications and mergers: I report them and have not explained them one by one.
