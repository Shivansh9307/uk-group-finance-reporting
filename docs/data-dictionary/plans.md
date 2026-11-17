# Data dictionary: spending plans

What `ukfr build` puts in the database for the plans a budget is compared with: OSCAR Plans (FY2017-18 to
FY2021-22), the Estimates "Departmental DEL budgets" tables (FY2022-23 to FY2026-27) and the PESA tables
(departmental AME and administration budgets to FY2028-29). Amounts are GBP thousands, spending positive.
Every claim is labelled **tested** (the test or command) or **designed** (not run).

How the sources were chosen and profiled is in [../profiling/plan-sources.md](../profiling/plan-sources.md)
and [../profiling/oscar-annual-extracts.md](../profiling/oscar-annual-extracts.md); this page describes what
was built from them.

## Where the files are

The Estimates and PESA workbooks are small (316 KB and 800 KB), so they are committed under
`data/committed/estimates_del/<release>/` and `data/committed/pesa/<release>/` with the same sha256 as
before (**tested**: `ukfr fetch --verify`, 48 committed files ok, 0 failures). They load in the committed
scope, which CI runs. The OSCAR Plans come from the five November 2022 annual extracts under
`$UKFR_DATA_DIR` (about 270 MB of Deflate64 zips read as streams, never written to disk), so that stage is
`plans_oscar`, scope `full`, and its tests carry `-- marker: localdata`.

## Tables

| Table | Rows, committed scope | Rows, full scope | Grain |
|---|---|---|---|
| `raw.plan_source_file` | 16 | 21 | one workbook or extract zip |
| `raw.plan_estimates` | 659 | 659 | sheet x row x year, as published |
| `raw.plan_pesa` | 31,289 | 31,289 | sheet x row x year, as published (PESA 2022 to 2026, the December 2025 update and SR25) |
| `raw.plan_oscar` | 0 | 135,958 | one PLANS row of an extract |
| `raw.plan_oscar_expected` | 0 | 1,639 | control figures from two csv files in git |
| `authored.plan_name_map`, `authored.sr_group`, `authored.plan_source` | 97, 31, 17 | same | the three authored files, as text |
| `stg.plan_name_map`, `stg.sr_group`, `stg.plan_source` | 97, 31, 17 | same | the same, typed and checked |
| `stg.plan_estimates_line` | 659 | 659 | a typed Estimates cell |
| `stg.plan_pesa_line` | 9,826 | 9,826 | a typed cell of a nominal department-group table |
| `stg.plan_oscar` | 0 | 14,960 | financial year x organisation x economic category x control budget detail x economic budget |
| `dw.dim_sr_group` | 31 | 31 | one Spending Review group or non-department member |
| `dw.dim_plan_source` | 16 | 17 | one plan source and edition |
| `dw.dim_plan_grain` | 4 | 4 | grain code A to D |
| `dw.fact_plan` | 749 | 5,372 | see below |
| `dw.plan_coverage` | 35 | 69 | year x plan source x measure x grain |
| `audit.plan_sheet_control` | 384 | 384 | one control row per section and year of a plan table |
| `audit.plan_coverage` | 35 | 69 | copy of `dw.plan_coverage`, written to `evidence/build/` |

Row counts come from `evidence/build/table_counts.csv` (committed scope, the copy under git) and from a
full-scope build (`table_counts.csv` written to a scratch directory). The raw tables hold every cell
the reader parsed, including the sections that never reach the fact (total managed expenditure, real terms,
national-accounts adjustments), so that nothing is lost on landing.

## Raw tables

`raw.plan_estimates` and `raw.plan_pesa` have the same columns: `file_id`, `source_row` (row of the sheet,
1-based), `sheet`, `table_title`, `unit` (as written; the pound sign is U+FFFD in some workbooks),
`section` (last heading above the row), `row_label` (as written, footnote marker included), `row_label_clean`
(markers removed by `ukfr.readers.plans.clean_name`), `row_kind` (`line`, `total` or `memo`, as the reader
classified it), `year_label`, `status_label` (`plans` or `outturn` as written above or below the year),
`value_text` (the number as read, 15 significant digits) and `value_published` (the same as
`DECIMAL(38,18)`). A dash or blank cell is NULL. Nothing is converted to GBP thousands in Python:
**tested**, `sql/tests/507_plan_amounts_converted.sql` (every value has a recognised unit and
`amount_k` equals value x multiplier to four decimal places).

`raw.plan_oscar` holds the 21 columns of an extract row that the plan needs, as text, for the rows whose
`VERSION_CODE` is `PLANS`: 22,650 + 32,770 + 30,977 + 29,665 + 19,896 = 135,958 rows. **Tested**
(localdata): `sql/tests/520_oscar_plans_rows_and_totals.sql` compares the rows read per extract with
`plans_rows` in `data/audit/extract_file_control_totals.csv`.

37 of those rows carry `USAGE_CODE = OUTTURN` although their version is PLANS (24 and 13 rows; DHSC
pension, housing revenue account and London Underground lines and a few small bodies). They are inside the
control totals that the profiling published, so they stay in; the count is pinned by
`sql/tests/521_oscar_plans_keys_and_fact.sql` so a change is noticed. I have not tried to decide whether
they are real plan lines.

## Estimates and PESA lines (stg)

`stg.plan_estimates_line` and `stg.plan_pesa_line` add to each cell:

- `unit_multiplier` (billion 1,000,000, million 1,000) and `amount_k` = value x multiplier, `DECIMAL(19,4)`;
- `measure_from_title`, read from the **sheet title**, never the sheet name (the 2022-23 Supplementary
  Estimate calls its excluding-depreciation sheet `RDEL`); **tested**,
  `pipeline/tests/test_plans_sql.py::test_estimates_measure_comes_from_the_sheet_title` compares all 27
  Estimates sheets with the profiling inventory, and `::test_pesa_department_group_sections_equal_the_profiling_inventory`
  compares the T-SQL section rules with the profiling's Python rules;
- `measure`, which differs only where the authored plan source says a table is not titled "excluding
  depreciation" but is on that basis (2026-27 Main Estimate, PESA 2026 administration table);
- for Estimates, `is_final_plan` (Supplementary Estimate first, then out-of-turn, then Main), **tested**:
  the 14 sheets the profiling marked `yes`;
- `target_type`, `target_name` and `line_role` from the authored name map.

Measures: `RDEL` (resource DEL including depreciation), `RDEL_EX_DEPN`, `CDEL`, `TDEL`,
`RESOURCE_DEPT_AME`, `CAPITAL_DEPT_AME`, `ADMIN`, `ADMIN_EX_DEPN`. Estimates sheets for the tax-changes
allowance (`RDEL_EX_DEPN_TAX_ALLOWANCE`, 2025-26 Main Estimate) are kept in stg but never used: it is an
allowance for employer National Insurance, not a budget.

## The name map and `dw.dim_sr_group`

`authored/plan_name_map.csv` (97 rows) maps each published plan-source name to one member of
`authored/sr_group.csv`: the 23 Spending Review groups with the names and codes of `BUD_24-25.xlsx` (the
November 2025 annual release), `Single Intelligence Account` (`plan_only`), `Combined pre-2023: BEIS, DCMS
and DIT` (`combined_pre_2023`) and six `non_department` members (Reserves; OBR allowance for shortfall;
Budget Exchange adjustment; Unallocated central funds; Memo and accounting lines; Central exchequer and local
government lines). Each map row has `evidence`, `note` and a `confidence`. `line_role` is `whole`, `part`
(Transport and High Speed 2, Energy Security and Net Zero and Sizewell C are published as two lines with no
parent, so the parts are added into one row) or `component` (already inside another line, never added: the
Scottish block grant adjustment line, `Reserve excluding retained Budget Exchanges`, ratios and SR25 memo
lines).

Two families of names: `hmt_tables` (Estimates, PESA, SR25) and `oscar_extract` (the `SR_GROUP_LONG_NAME` in
the extracts, which are on the structure of November 2022). The old extract groups map as follows: BIS
(which is the BEIS department), Department for International Trade, Energy and Climate Change and
Culture, Media and Sport map to the combined pre-2023 group; the Foreign and Commonwealth Office and
International Development map to the Foreign, Commonwealth and Development Office; Exiting the European
Union maps to the Cabinet Office (confidence medium: the department closed in January 2020 and its functions
went to the Cabinet Office, which the data cannot show; 187 plan rows in four years); `n/a` maps to the
central exchequer member.

Checks, all **tested**:

- the authored files are typed and validated in `sql/stg/500_plan_authored.sql`, which stops the build with a
  message on a duplicate key, a value outside its list, a target that is not a member of the group list or a
  row without evidence or note;
- `sql/tests/505_plan_lines_all_mapped.sql`: every Estimates and PESA line and every OSCAR SR group has a
  map row, every target exists in `dw.dim_sr_group` with the same type, nothing is unmapped;
- `sql/tests/506_sr_group_members.sql`: the 23 names are exactly those of the latest BUD, one plan-only
  member, one combined member, the non-department members;
- the lower-case and upper-case spellings of "DLUHC Levelling Up, Housing and Communities" are one row,
  because the database collation is case-insensitive.

`dw.dim_sr_group` columns: `sr_group_key` (row number in a fixed order), `sr_group_code`, `sr_group_name`,
`member_type`, `is_department_group`, `has_outturn`, `description`, `evidence`. It is authored and holds no
amount (**tested**, `sql/tests/512_authored_data_never_reaches_a_total.sql`).

## `dw.dim_plan_source`

One row per plan source and edition: OSCAR Plans (November 2022 extracts), the nine Estimates workbooks
(Main, out-of-turn Supplementary and Supplementary per year), the PESA editions 2022, 2023, 2024, July 2025,
December 2025 and 2026, and SR25. In a committed-scope build the OSCAR row is absent. Columns:
`plan_source_key` (follows the order of `authored/plan_source.csv`, so it is the same in both scopes),
`plan_source_code`, `family`, `edition`, `edition_label`, `plan_year` (Estimates only), `first_published`,
`file_count`, `filename`, `sha256`, `grain_description`, `plan_basis`, `includes_block_grant_adjustment`,
`scotland_bga_flag`, `scotland_bga_rule`, `resource_basis`, `resource_basis_evidence`,
`is_final_plan_for_year` and `fact_plan_rows`.

`scotland_bga_flag`:

| Value | Meaning | Sources |
|---|---|---|
| `gross_of_bga` | the Scotland line is before the block grant adjustment | Estimates 2022-23 (three workbooks), 2023-24 Main, 2024-25 Supplementary, 2025-26 Main and Supplementary |
| `net_of_bga` | the line is after the adjustment; the adjustment must be added back to compare with outturn that is before it | Estimates 2023-24 Supplementary (26.3bn against 37.4bn in PESA 2024) and 2026-27 Main (27.4bn, memo line of -16.05bn) |
| `same_as_oscar_outturn` | OSCAR plan and outturn are on one basis | OSCAR Plans |
| `not_applicable` | the rows used are AME or administration, or none is used | PESA, SR25 |

**Tested**: `sql/tests/511_scotland_bga_flags_agree_with_data.sql` checks every gross line is within 10% of a
PESA Scotland figure on the excluding-depreciation basis for the same year, and every net line is at least
15% below it (or, for 2026-27, has the memo line). The rule rests on magnitudes: the reader does not keep the
footnote text, and I did not check the footnotes by eye.

`resource_basis = ex_depreciation` for the 2026-27 Main Estimate and PESA 2026. Evidence (**tested**,
`sql/tests/537_estimates_2026_27_matches_pesa_2026.sql`): each department line of the 2026-27 Main Estimate
equals PESA 2026 Table 1.3 resource DEL for 2026-27 to the nearest million, and the totals agree to GBP 5m
once reserves, the OBR allowance and the Budget Exchange adjustment are taken out. For the PESA 2026
administration table: 2024-25 total 12,315 (2026 Table 1.5) against 12,283 excluding depreciation and 13,001
including it in the December 2025 update (a comparison of three published totals that I read by eye; no test).

## `dw.fact_plan`

| Column | Meaning |
|---|---|
| `plan_fact_key` | row number in the order of the natural key below |
| `plan_source_key` | `dw.dim_plan_source` |
| `financial_year` | `2022-23` |
| `sr_group_key` | `dw.dim_sr_group` |
| `organisation_code` | OSCAR organisation, NULL for grains B, C and D |
| `control_budget_detail` | OSCAR: `DEL PROG`, `DEL ADMIN`, `DEPT AME`, `NON-DEPT AME`, `NON-BUDGET`; Estimates: `DEL` (programme and administration together); PESA: `DEPT AME`, `DEL ADMIN` |
| `economic_budget` | `RESOURCE`, `CAPITAL`, `n/a` |
| `measure` | `RDEL` and `CDEL` (OSCAR, resource includes depreciation), `RDEL_EX_DEPN`, `CDEL`, `RAME`, `CAME`, `ADMIN`, `ADMIN_EX_DEPN`, `NON_DEPT_AME`, `NON_BUDGET`, `UNCLASSIFIED` |
| `amount` | `DECIMAL(19,4)`, GBP thousands |
| `grain_code` | A to D, see below |
| `source_line_count` | published lines or extract rows added into the row |
| `is_part_of_other_measure` | 1 for administration budgets: they are part of resource DEL, never add them to it |

The natural key (`plan_source_key`, `financial_year`, `sr_group_key`, `organisation_code`,
`control_budget_detail`, `economic_budget`, `measure`) is unique (**tested**, `sql/tests/508_fact_plan_grain.sql`,
and a unique index).

| Grain | Source | Years | Grain |
|---|---|---|---|
| A | OSCAR Plans | FY2017-18 to FY2021-22 | year x organisation x control budget detail x economic budget (the load grain is organisation x economic category; the fact sums over category) |
| B | Estimates, final plan of the year | FY2023-24 to FY2026-27 | year x Spending Review group x measure (`RDEL_EX_DEPN`, `CDEL`) |
| C | Estimates 2022-23 Supplementary | FY2022-23 | the same lines, but BEIS, DCMS and DIT are one combined group; compare with outturn only at that group and at total DEL |
| D | PESA, latest edition that still calls the year `plans` | FY2022-23 to FY2028-29 | year x group x `RAME`, `CAME`, `ADMIN`, `ADMIN_EX_DEPN` |

Plans are loaded for FY2017-18 to FY2021-22 (the profiling found all five usable), not only the three
years the 8,902 count was given for: `stg.plan_oscar` has 2,965, 3,093, 3,225, 2,885 and 2,792 keys, and
3,225 + 2,885 + 2,792 = 8,902 for FY2019-20 to FY2021-22 (**tested**, `sql/tests/520_oscar_plans_rows_and_totals.sql`).
Keys that net to zero are kept. Measure `UNCLASSIFIED` is the few DEL rows whose economic budget is `n/a`
(under GBP 1bn in total; 1 to 2 keys a year).

Grain C is a reading of "FY2022-23 at total DEL only, with the combined group kept visible": I load the
group lines as published so that the year ties to the sheet total, give the three reorganised departments
one member, and say in the grain description that a group variance is valid only at that member and at the
total. If the model should hide group variance for this year, it can do so with the grain code.

Single Intelligence Account and the non-department lines stay in the fact so that sums tie. **Tested**,
`sql/tests/509_fact_plan_ties_to_published_totals.sql`: for every Estimates and PESA year and measure the
sum of the fact rows equals the sheet's own published total row (converted) within the rounding of the
published figures. The total row is a cell the reader returns like any other; the load does not sum it.
For grain A: `sql/tests/512_...` (fact total equals the OSCAR total) and
`sql/tests/520_...` (every year x department group x control budget detail x economic budget equals
`plan_oscar_totals.csv`, amounts and row counts; the csv was produced by the profiling code with its own
aggregation but through the same extract reader, so it checks the load, not the reader).

Which PESA edition feeds a year: the latest edition that still labels the year `plans` for that kind of
budget (resource AME, capital AME, administration). **Tested**: no year has two (`508`).

## Controls

`audit.plan_sheet_control` (written to `evidence/build/plan_sheet_control.csv`): for each section and year of
every Estimates sheet and every nominal PESA/SR25 department-group table, the lines above the first total row
against that total, with a tolerance of (lines + 1) x half a unit of the last published digit (at most 9
places, because SR25 is unrounded). **Tested**: all 27 Estimates sheet-years pass and no PESA or SR25
section fails (`sql/tests/501_plan_sheets_equal_published_totals.sql`). Two PESA capital AME sections have
no total for 2029-30 and are listed as `no total`. Lines below the first total (the Scottish block grant
adjustment line of PESA 2026 Table 1.3) belong to a later total and are not added.

Not covered: the PESA total managed expenditure tables, the real-terms tables and the national-accounts
tables; they are in `raw.plan_pesa` but not in stg.

FY2023-24 consistency (`plan-sources.md` section 13): **tested**,
`pipeline/tests/test_plans_sql.py::test_fy2023_24_consistency_figures_are_reproduced` reproduces, to the
pound thousand, the Estimates 2023-24 Supplementary plan, the PESA 2023 plan and the PESA 2024 outturn for
every group and measure in `plan_consistency_2023_24.csv`, and the mapped-groups total rows. The BUD outturn
column needs the annual BUD, which is not loaded by this change, so it is not checked here.

## Coverage matrix

Rows in the fact and total in GBP billion (`rows / total`), by grain, plan source, measure and financial year,
from the full-scope build (`audit.plan_coverage`; the committed-scope copy in `evidence/build/` has no grain A
rows). Administration rows are a part of resource DEL and overlap it.

| Grain | Plan source | Measure | 2017-18 | 2018-19 | 2019-20 | 2020-21 | 2021-22 | 2022-23 | 2023-24 | 2024-25 | 2025-26 | 2026-27 | 2027-28 | 2028-29 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | OSCAR_PLANS_2022_11 | CAME | 37 / 26.2 | 37 / 25.5 | 38 / 28.0 | 37 / 59.7 | 43 / 33.6 |  |  |  |  |  |  |  |
| A | OSCAR_PLANS_2022_11 | CDEL | 170 / 57.6 | 172 / 64.6 | 182 / 72.0 | 176 / 99.3 | 160 / 98.2 |  |  |  |  |  |  |  |
| A | OSCAR_PLANS_2022_11 | NON_BUDGET | 212 / 1,474.8 | 212 / 1,499.0 | 215 / 1,572.2 | 215 / 1,690.2 | 218 / 1,587.2 |  |  |  |  |  |  |  |
| A | OSCAR_PLANS_2022_11 | NON_DEPT_AME | 15 / 130.4 | 17 / 125.4 | 16 / 129.4 | 16 / 129.1 | 18 / 114.5 |  |  |  |  |  |  |  |
| A | OSCAR_PLANS_2022_11 | RAME | 151 / 492.9 | 159 / 313.3 | 168 / 458.4 | 160 / 618.9 | 148 / 762.8 |  |  |  |  |  |  |  |
| A | OSCAR_PLANS_2022_11 | RDEL | 312 / 339.8 | 344 / 344.3 | 353 / 370.4 | 308 / 537.8 | 308 / 490.1 |  |  |  |  |  |  |  |
| A | OSCAR_PLANS_2022_11 | UNCLASSIFIED | 1 / 0.3 | 1 / 0.0 | 2 / 0.0 | 2 / 0.4 |  |  |  |  |  |  |  |  |
| B | EST_2023_24_SUPPS | CDEL |  |  |  |  |  |  | 23 / 110.7 |  |  |  |  |  |
| B | EST_2023_24_SUPPS | RDEL_EX_DEPN |  |  |  |  |  |  | 24 / 449.1 |  |  |  |  |  |
| B | EST_2024_25_SUPPS | CDEL |  |  |  |  |  |  |  | 23 / 114.6 |  |  |  |  |
| B | EST_2024_25_SUPPS | RDEL_EX_DEPN |  |  |  |  |  |  |  | 24 / 487.5 |  |  |  |  |
| B | EST_2025_26_SUPPS | CDEL |  |  |  |  |  |  |  |  | 23 / 130.7 |  |  |  |
| B | EST_2025_26_SUPPS | RDEL_EX_DEPN |  |  |  |  |  |  |  |  | 24 / 515.2 |  |  |  |
| B | EST_2026_27_MAINS | CDEL |  |  |  |  |  |  |  |  |  | 23 / 135.3 |  |  |
| B | EST_2026_27_MAINS | RDEL_EX_DEPN |  |  |  |  |  |  |  |  |  | 24 / 520.0 |  |  |
| C | EST_2022_23_SUPPS | CDEL |  |  |  |  |  | 20 / 107.6 |  |  |  |  |  |  |
| C | EST_2022_23_SUPPS | RDEL_EX_DEPN |  |  |  |  |  | 21 / 452.5 |  |  |  |  |  |  |
| D | PESA_2022 | ADMIN |  |  |  |  |  | 17 / 13.4 |  |  |  |  |  |  |
| D | PESA_2022 | ADMIN_EX_DEPN |  |  |  |  |  | 17 / 12.1 |  |  |  |  |  |  |
| D | PESA_2022 | CAME |  |  |  |  |  | 15 / 40.2 |  |  |  |  |  |  |
| D | PESA_2022 | RAME |  |  |  |  |  | 21 / 510.5 |  |  |  |  |  |  |
| D | PESA_2023 | ADMIN |  |  |  |  |  |  | 20 / 13.7 |  |  |  |  |  |
| D | PESA_2023 | ADMIN_EX_DEPN |  |  |  |  |  |  | 20 / 12.0 |  |  |  |  |  |
| D | PESA_2023 | CAME |  |  |  |  |  |  | 20 / 96.7 |  |  |  |  |  |
| D | PESA_2023 | RAME |  |  |  |  |  |  | 24 / 504.1 |  |  |  |  |  |
| D | PESA_2024 | ADMIN |  |  |  |  |  |  |  | 20 / 14.0 |  |  |  |  |
| D | PESA_2024 | ADMIN_EX_DEPN |  |  |  |  |  |  |  | 20 / 12.1 |  |  |  |  |
| D | PESA_2024 | CAME |  |  |  |  |  |  |  | 21 / 102.7 |  |  |  |  |
| D | PESA_2024 | RAME |  |  |  |  |  |  |  | 24 / 551.8 |  |  |  |  |
| D | PESA_2025_12 | ADMIN |  |  |  |  |  |  |  |  | 20 / 16.0 |  |  |  |
| D | PESA_2025_12 | ADMIN_EX_DEPN |  |  |  |  |  |  |  |  | 20 / 14.6 |  |  |  |
| D | PESA_2025_12 | CAME |  |  |  |  |  |  |  |  | 21 / 74.8 |  |  |  |
| D | PESA_2025_12 | RAME |  |  |  |  |  |  |  |  | 24 / 581.9 |  |  |  |
| D | PESA_2026 | ADMIN_EX_DEPN |  |  |  |  |  |  |  |  |  | 20 / 14.8 | 20 / 14.0 | 20 / 13.3 |
| D | PESA_2026 | CAME |  |  |  |  |  |  |  |  |  | 22 / 79.6 | 21 / 62.3 | 21 / 61.9 |
| D | PESA_2026 | RAME |  |  |  |  |  |  |  |  |  | 24 / 655.1 | 24 / 642.0 | 24 / 648.9 |

## Timings

Full build on the development machine with other builds running at the same time (so slower than a quiet
machine), **tested** on 17 November 2026: `ukfr build --scope full --recreate --yes` took 11 min 59 s: the
in-year stage 445.0 s, stage `plans` 1.5 s, stage `plans_oscar` 237.3 s (five extracts, 12 GB of text
decompressed, 135,958 rows kept), derived SQL 29.9 s. The committed-scope build of the same code took 9 min 20 s
in a busy period (in-year stage 480.3 s, stage `plans` 7.7 s, derived SQL 66.3 s); the plan stage itself takes
a few seconds.

## Not done here

- The BUD and PSS are not loaded, and there is no phasing profile or plan-basis outturn in this change.
- `UNCLASSIFIED`, the 37 `OUTTURN`-usage rows and the Scotland rule above are open questions that I flag
  rather than settle.
- FY2022-23 plans on the new departments cannot be built: no source publishes the split.
