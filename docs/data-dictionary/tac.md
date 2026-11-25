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
expects; a report that wants the OSCAR sign has to flip it itself.

## What the model and the audits read

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


## Statutory statements: the derived cash flow and the elimination-gap control

What `sql/stg/150`, `sql/dw/150` and `155`, `sql/audit/150` to `165` and `sql/tests/150` to `159` add on top of the tables above. Every
claim is labelled **tested** (command and result file) or **designed**. The numbers are from the full build of 2026-11-24
(`ukfr build --scope full --recreate --yes`, green in 22 min 4 s) and the tables under `evidence/full/`.

### Sign

The model shows the TAC sign as published: income, assets and inflows positive, expenses, liabilities and outflows negative. I did
not convert it to the OSCAR sign (spending positive, income negative), for three reasons: every figure then ties to the printed
statement and to the consolidated accounts it is compared with, which print the same sign; the balance sheet and the cash flow have
no OSCAR counterpart to flip to; and a reader of a mixed page would otherwise meet two conventions on one screen. Every TAC page
says "TAC sign" in its subtitle. `dw.tac_statutory_line.expected_sign` stays in the dictionary, and a subtotal or total is never
added to its components (the line kind is authored, `authored/tac_line_role.csv`).

### Objects

| Object | Grain | What it is |
|---|---|---|
| `dw.tac_cash_flow_line` | derived line | **authored** (`authored/tac_cash_flow_line.csv`, 22 rows): the lines of the derived cash flow, their section and whether they are compared with published lines |
| `dw.tac_cash_flow_derived` | provider x year x derived line, 28,248 rows | **derived**: the indirect cash flow (below). Every row flagged `is_derived`; never in a real total |
| `dw.tac_cash_flow_comparison` | published line | **authored** (`authored/tac_cash_flow_map.csv`, 148 rows, a note on each): which derived line each of the 51 published cash-flow lines is compared with |
| `dw.tac_control_line`, `dw.tac_control_member` | 6 lines; 54 line memberships | **authored** (`authored/tac_control_line.csv`): the control lines and the provider statement lines (never a subtotal) they are made of |
| `dw.tac_consolidated_control` | printed line x year, 48 rows | **authored, hand-keyed** (`authored/tac_consolidated_control.csv`): values printed in the consolidated NHS provider accounts, GBP million, with printed and PDF page |
| `audit.tac_cash_flow_tie` | year x tie, 66 rows | what the published cash flow says about itself and how the derived cash flow ties to the balance sheet |
| `audit.tac_cash_flow_line_residual`, `audit.tac_cash_flow_section_residual` | year x derived line (132); year x section (30) | derived against published, residual not forced |
| `audit.tac_elimination_gap`, `audit.tac_elimination_gap_excluded` | year x control line (36); excluded year x control line (12) | provider sum against consolidated; the figures of the providers the TAC file leaves out |
| `dw.v_model_tac_*` (8 views, `sql/audit/150`, `151`) | | what the model reads; the restatement of `audit.tac_prior_year_difference` is a column of the fact view |

### The derived (indirect) cash flow

A balance-sheet line contributes its **movement of the year**, the current-year column less the prior-year column of the *same file*, so
a restated opening balance never leaks in; an income-statement line contributes its current-year flow. Each input has a factor in the
authored map: -1 for an asset or a liability (an increase uses cash), +1 for equity, and for the income-statement lines +1 into
their section and -1 out of the movement of the income and expenditure reserve, so the surplus is counted once. Every balance-sheet
line other than cash feeds exactly one derived line (**tested**: `sql/tests/150`). Adding the derived lines equals the balance sheet
cash movement in every provider-year to within GBP 1,730 (the balance sheets balance to less than GBP 1,000 each side; 20 of
1,284 provider-years differ by GBP 1,000 or more, none by 2,000 or more; `sql/tests/152`, `audit.tac_cash_flow_tie`).

Residual = derived less published, added over providers (GBP million, `evidence/full/tac_cash_flow_section_residual.csv`):

| Year | Operating | Investing | Financing | Reserve movements (derived only) | Net change: derived | Net change: published |
|---|---:|---:|---:|---:|---:|---:|
| 2019-20 | -2,690 | 2,501 | 298 | -84 | 1,004 | 980 |
| 2020-21 | -2,662 | 2,021 | 1,013 | -345 | 6,980 | 6,952 |
| 2021-22 | -2,506 | 2,448 | 591 | -499 | 1,838 | 1,804 |
| 2022-23 | -4,701 | -2,426 | 6,766 | 381 | -2,714 | -2,735 |
| 2023-24 | -5,822 | 4,828 | 6,091 | -5,075 | -1,896 | -1,918 |
| 2024-25 | -6,997 | 6,115 | 770 | 111 | -730 | -729 |

Why the residual is not zero (**tested** as a number, explained by line in `evidence/full/tac_cash_flow_line_residual.csv`; the explanation is mine). In 2024-25
the operating residual (-6,997) is almost entirely the published adjustments that neither primary statement shows on its face
(depreciation, impairments, donated income, the PFI credit and the pension adjustment, line `D_OP_NONCASH`: +6,848 published, 0 derived); the same
non-cash charges sit in the balance-sheet movement of property, plant and equipment, so investing is overstated (the
property line residual is +5,847, intangibles +523). Lines with no non-cash item tie exactly: the operating surplus, inventories and public
dividend capital (residual 0). Financing residuals are non-cash borrowing movements (new leases, accrued interest). The large
2022-23 to 2023-24 financing residuals are borrowings movements that the published cash flow shows as cash only in part (the year IFRS 16 right of use assets and
their liabilities entered the balance sheets, 1 April 2022); I did not test that reading line by line. Transfers by absorption and mergers are in the
reserve movements and in the investing residual.

The published cash flow ties to itself (**tested**: `sql/tests/151`, 0 provider-years breaking GBP 1,000 in all six years): each section subtotal equals the sum of
its published lines, the increase in cash equals the three subtotals, closing cash equals opening cash plus the adjustments, the increase
and the four reconciling lines, and the operating surplus the cash flow starts from equals the income statement's. It does **not**
equal the balance sheet cash movement in every provider-year: the published increase in cash differs from the
balance sheet movement by GBP 1,000 or more in 15, 19, 12, 4, 8 and 14 provider-years (2019-20 to 2024-25); with the reconciling lines added, in 5, 6, 4, 2, 4 and 2; and
closing cash of the cash flow differs from the balance sheet cash in 4, 2, 2, 1, 2 and 1 (`sql/tests/152` pins these counts). The remainder are cash defined
differently in the cash flow and on the balance sheet (the cash flow nets overdrafts); I have not examined each provider.

### The elimination gap

The sum of the provider accounts is not the consolidated group: the consolidated NHS provider accounts (published by DHSC on gov.uk with NHS
England, one report each year, registered as source `nhs_consolidated_accounts` with the sha256 of each of the six PDFs in
`data/manifest/files.csv`; **tested**: `ukfr fetch --source nhs_consolidated_accounts` downloaded 6 files, no error) eliminate balances and
transactions between providers. Eight printed lines are keyed for each year, 48 values, each with the printed page and the PDF page, from the PDF text of the
statement of comprehensive income and of financial position, and each value equals the comparative column of the next year's report where there is one (**tested**: `sql/tests/156`; none was restated). The four printed totals add up to the printed total assets employed in all six years.
Operating expenses are the column after revaluations, impairments and transfers, which is what the provider income statements report.

Gap = provider sum less consolidated, GBP million (`evidence/full/tac_elimination_gap.csv`):

| Year | Operating income | Operating expenses | Total assets | Total liabilities | Cash | Total assets employed |
|---|---:|---:|---:|---:|---:|---:|
| 2019-20 | 1,355 (1.5%) | -1,229 (1.3%) | 412 | -579 | -33 | -168 |
| 2020-21 | 2,268 (2.2%) | -2,257 (2.2%) | 735 | -706 | 0 | 29 |
| 2021-22 | 2,966 (2.6%) | -2,960 (2.7%) | 822 | -813 | 0 | 9 |
| 2022-23 | 3,224 (2.7%) | -3,219 (2.7%) | 1,521 | -1,497 | 0 | 24 |
| 2023-24 | 295 (0.2%) | -278 (0.2%) | -610 | -215 | -389 | -825 |
| 2024-25 | 267 (0.2%) | -270 (0.2%) | -570 | -325 | -343 | -895 |

What I can say, and what I cannot. Income and expenses are larger in the provider sum by nearly the same amount (within GBP 130 million in a year), and so are assets and liabilities, and the gap in total assets
employed is below GBP 30 million in 2020-21 to 2022-23 (below 0.1%): an elimination removes both sides of a balance, which is what the pattern shows. From 2023-24 the sign changes and net assets differ by -825 and -895: a provider whose accounts the TAC file leaves out
("excluded from this dataset": 1 provider in 2019-20, 5 in 2023-24, 3 in 2024-25) is in the consolidated accounts and not in the sum. Where the next year's prior-year column
exists, I read their figures from it (`audit.tac_elimination_gap_excluded`): in 2019-20 the one provider's cash is GBP 33.191 million, and the cash gap is -33.159 million; in 2023-24 three of the five have a prior-year column, with income of
1,858 million and assets of 1,186 million, which brings the income gap of 295 back to about 2,150, the size of the years before. That is a partial explanation, not a decomposition: the other two providers of 2023-24, the three of 2024-25
and the intra-NHS eliminations themselves are not separated, and I did not try to.
