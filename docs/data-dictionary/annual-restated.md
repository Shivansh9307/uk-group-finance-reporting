# Data dictionary: annual restated outturn (BUD) and the Public Spending Statistics

What `ukfr build --scope full` adds to the database from the 15 annual restated OSCAR workbooks ("BUD",
three vintages: November 2023, 2024 and 2025) and from the Public Spending Statistics (PSS) database of
July 2026. Both sets of files are under `$UKFR_DATA_DIR`, not in git, so everything on this page is built
only by a full build; a committed-scope build skips it (**tested**, see Results). Amounts are GBP
thousands, spending positive, income negative. Every claim is labelled **tested** (with where) or
**designed**.

Everything is real data except one authored table, the register entry below.

## Register of authored data

| Object | What it is | Why | Where it can reach |
|---|---|---|---|
| `authored.pss_sr_group_alias` | three rows: `Scottish Government` -> `Scotland`, `Welsh Government` -> `Wales`, `Northern Ireland Executive` -> `Northern Ireland` | the PSS names three Spending Review groups after the devolved administration and OSCAR names them after the nation; the other 20 PSS group names equal OSCAR's exactly | only `stg.pss_sr_group_map`, which decides which OSCAR group a PSS row is compared with. It holds no amount. **Tested**: `sql/tests/411_pss_sr_group_map_complete.sql` (every PSS name matched, exactly three through an alias, each target exists, no numeric column) |

## Tables

| Table | Rows | Grain | Key |
|---|---|---|---|
| `raw.oscar_bud` | 515,949 | one data row of a BUD workbook | (`file_id`, `source_row`) |
| `raw.oscar_bud_file` | 19 | one file of the annual releases: 15 workbooks loaded, 4 guidance files skipped | `file_id` |
| `raw.oscar_bud_control_expected` | 15 | one workbook in `data/audit/bud_file_control_totals.csv` | (`vintage`, `filename`) |
| `raw.oscar_bud_independent_expected` | 15 | one workbook in `data/audit/bud_independent_control.csv` | (`vintage`, `filename`) |
| `quarantine.oscar_bud` | 0 | one rejected row | (`file_id`, `source_row`) |
| `raw.pss` | 41,171 | one data row of the PSS `Database` sheet | (`file_id`, `source_row`) |
| `raw.pss_file` | 2 | one PSS file: the database (loaded) and the Chapter 1 tables (skipped) | `file_id` |
| `raw.pss_control_expected`, `raw.pss_independent_expected` | 5 each | one financial year | (`filename`, `financial_year`) |
| `quarantine.pss` | 0 | one rejected row | (`file_id`, `source_row`) |
| `stg.bud_department_group_map` | 206 | vintage x department group x SR group x PESA group, as written | primary key on all of them |
| `stg.bud_organisation_type` | 904 | vintage x organisation x type x department group, as written | primary key on all of them |
| `stg.bud_account_hierarchy` | 128 | economic category x group x budget, as written | primary key on all of them |
| `stg.bud_sr_group_by_organisation` | 3,967 | vintage x financial year x organisation | (`vintage`, `financial_year`, `organisation_code`) |
| `stg.pss_outturn` | 41,171 | one PSS row, typed | (`file_id`, `source_row`) |
| `stg.pss_sr_group_map` | 23 | one PSS group name | `pss_sr_group_name` |
| `authored.pss_sr_group_alias` | 3 | one alias | `pss_sr_group_name` |
| `dw.fact_outturn_annual` | 97,250 | vintage x financial year x organisation x economic category x control budget detail x economic budget x ringfence x TYPE layer | the grain |
| `audit.bud_file_control` | 15 | one workbook | `file_id` |
| `audit.bud_vs_inyear_del` | 60 | financial year x vintage x level | the three |
| `audit.pss_vs_outturn` | 443 | comparison x year x level x SR group x measure | the five |
| `audit.bud_inyear_org_match` | 313 | one organisation code | `organisation_code` |

Row counts are from `evidence/build`-style export of the full build (**tested**: the full build's
`table_counts.csv`, and `sql/tests/400` to `412`).

## What is loaded, and what is skipped

- **Workbooks.** `raw.oscar_bud` holds every data row of the 15 `BUD*.xlsx` files, read through
  `ukfr.readers.oscar_bud`: the 90 text columns of the sheet in lower case, `amount_text` (the AMOUNT cell as
  read) and `amount` (`DECIMAL(38,10)`, exact; every real amount is a whole number). Lineage is `file_id`,
  `source_row` (header = 1) and `vintage`.
- **Skipped on purpose.** The four "Understanding OSCAR" guidance files (a 2022 xlsx, 2023 and 2024 PDFs,
  a 2025 docx) hold no data rows. They are listed in `raw.oscar_bud_file` with `file_kind = 'guidance'`,
  `load_status = 'skipped'`, a reason and their hash. The PSS `July_PSS_2026_Chapter_1.xlsx` (Chapter 1
  summary tables, not the database sheet) is listed the same way in `raw.pss_file`. **Tested**:
  `sql/tests/402_bud_file_lineage_and_guidance_skipped.sql`, `410_pss_raw_equals_control_csv.sql`.
- **Quarantine.** A row is rejected, never dropped, for `amount_blank`, `amount_scale` (more than ten
  decimal places) or `amount_range` (28 or more integer digits). The real files have none
  (**tested**: `sql/tests/403_bud_pss_nothing_quarantined.sql`). An unknown header stops the build for the
  whole file, as for the in-year load.

## dw.fact_outturn_annual

Annual restated outturn: the sum of the workbook rows at the grain above. The BUD has annual figures only
(every row is period `P00`), so sub-segments, chart-of-accounts codes and months are summed away.

| Column | Meaning |
|---|---|
| `vintage` | the annual release, `2023-11`, `2024-11` or `2025-11`; the same year is restated in later vintages, so it is part of the key |
| `financial_year` | `2022-23`, from `YEAR_NO` |
| `organisation_code`, `economic_category_code` | source codes |
| `control_budget_detail_code` | `CONTROL_BUDGET_L0_LONG_NAME`: `DEL ADMIN`, `DEL PROG`, `DEPT AME`, `NON-DEPT AME`, `NON-BUDGET` |
| `economic_budget_code`, `economic_ringfence_code` | `RESOURCE`, `CAPITAL`, `OTHER NON-BUDGET`, `n/a`...; `RINGFENCED`, `NON-RINGFENCED`, `GENERAL CAPITAL`... |
| `type_code` | the TYPE layer (`TYPE_INYEAR`, `TYPE_OUTTURN`, `TYPE_MOG`, ...) |
| `control_budget_code` | `DEL`, `AME` or `NON-BUDGET` (`CONTROL_BUDGET_L1_LONG_NAME`); it follows from the detail (**tested**: `405`) |
| `amount` | `DECIMAL(19,4)`, sum of the rows |
| `source_rows` | workbook rows summed into the fact row |
| `is_latest_vintage` | the newest annual release loaded |
| `is_dept_group_scotland` | the organisation is in `SCT075.GROUP`, the Scottish Government group. PSS takes the block grant adjustment off Scotland's resource DEL and OSCAR does not, so a comparison with PSS leaves Scotland out of resource DEL (or adds the adjustment); the adjustment itself comes from PESA and is not in this table |
| `basis_rdel_excl_depreciation` | control budget DEL, economic budget RESOURCE, and `ECONOMIC_RINGFENCE_CODE <> 'RINGFENCED'`: resource DEL excluding depreciation and other non-cash ringfenced items, the basis the plans use (**tested**: `405`) |

Rules (**tested**):

- **Every TYPE layer is summed.** The layers are reasons for change that stack, not alternatives.
- **`STATUS_CODE = 'Closed'` rows are excluded.** Every one repeats a row held under another status, so
  keeping them double counts. Their number and amount are recorded per workbook in `audit.bud_file_control`
  (`closed_rows`, `amount_closed`): 35 rows over the 15 workbooks. `Submitted` and `Locked` rows stay.
- **The fact sums to the workbook.** For every workbook, `dw.fact_outturn_annual` summed equals the
  control `amount_sum_excluding_closed` and holds `data_rows - closed_rows` source rows
  (`sql/tests/404_bud_fact_sums_equal_excluding_closed.sql`).
- **One row per grain** (`405`), and the grain is the primary key.
- **Keys are source codes.** No dimension is joined here.

## Reference maps

All four read `raw.oscar_bud` (every row, Closed ones included, since they repeat other rows and add no key)
and carry `is_latest_vintage`.

| Table | Maps | Notes |
|---|---|---|
| `stg.bud_department_group_map` | department group code -> name -> SR group -> PESA group, per vintage | `CLG085.GROUP` has two SR groups (`CLG Communities`, `CLG Local Government`) so the code is not a key to the SR group; its name is DLUHC in 2023-11 and MHCLG later |
| `stg.bud_organisation_type` | organisation code -> type (level 1) -> department group, per vintage | 321 codes, 307 in the latest vintage |
| `stg.bud_account_hierarchy` | economic category -> group -> economic budget, with the number of chart-of-accounts level 5 codes | 128 categories in 75 groups; one row per combination, not per vintage, because none changes |
| `stg.bud_sr_group_by_organisation` | organisation -> SR group and department group, per vintage and year | **the key is the organisation**; within one workbook an organisation has exactly one of each (**tested**: `406`); `CLG085.GROUP` maps to two SR groups here too (**tested**: `407`) |

**Tested**: `pipeline/tests/test_bud_reference_maps.py` compares the first three with
`docs/profiling/data/bud_department_group_map.csv`, `bud_organisation_type.csv` and `bud_account_hierarchy.csv`
(same keys, vintages, years, row counts, latest flag; the profile's `variants_for_code` is not stored). They
agree exactly. The fourth map has no profiling file; the test checks that every (department group, SR group)
pair it carries is a pair of the department group map.

## Controls

**audit.bud_file_control**, one row per workbook, every measure `pass` or `fail`, **tested** (all 15 pass):
hashes (file, manifest, control CSV, independent CSV), rows (read = loaded + quarantined = control =
independent), Closed rows, the sum of all rows, the sum without Closed rows, the DEL, AME and non-budget sums
without Closed rows, and the fact table's sum.

**Independent recomputation**, `data/audit/bud_independent_control.csv` (and `pss_independent_control.csv`),
written by `uv run --project pipeline ukfr control bud` (and `pss`). The module
`ukfr.controls.bud_independent` opens each sheet with `python-calamine`, finds `AMOUNT`, `STATUS_CODE` and
`YEAR_NO` by their header text, and sums with `Decimal`. It does not import the readers (**tested**:
`pipeline/tests/test_bud_pss_load.py`, an import check, and a rerun that reproduces the committed files).
The loaded data agrees with it for every workbook and year (**tested**: `sql/tests/401`, `410`). What this
does not catch: a fault that both routes share, such as `python-calamine` reading a cell wrongly.

**audit.bud_vs_inyear_del**: for each financial year and each vintage that holds it, the June in-year
release of the following year (`stg.release.highest_period = 12`) against the BUD. Levels `DEL`, `AME`,
`NON-BUDGET` and `TOTAL`. `DEL` has a pass flag at 3.5% of the BUD amount; the others are
`boundary difference` and never a failure (the restated files carry non-budget layers the in-year files do
not, and AME is loaded after June). **Tested**: all 15 DEL pairs pass (largest gap 3.40%, 2023-24 against
the 2024-11 vintage). The BUD amounts equal `bud_inyear_reconciliation_total.csv` exactly and the in-year
amounts to within 0.01 (the staging table keeps four decimals and drops exact zeros); all 60 rows
(`sql/tests/408`, `pipeline/tests/test_bud_reference_maps.py`).

**audit.pss_vs_outturn**: the PSS against OSCAR by year, SR group and measure (resource DEL excluding
depreciation, capital DEL).

- `BUD` rows use `dw.fact_outturn_annual` from the latest vintage holding the year (2021-22 to 2024-25) on
  the exact basis (ringfence column). `IN-YEAR` rows use the June release (2021-22 to 2025-26), which has
  no ringfence column, so resource excluding depreciation drops the PESA economic group `DEPRECIATION` and
  leaves impairments and other non-cash items in (about 5.5bn from 2024-25).
- Levels: `SR GROUP` (status `recorded`: money moves between groups, so no group-level tolerance), `TOTAL`,
  and `TOTAL EXCL SCOTLAND`, the graded control row (Scotland's block grant adjustment is in the PSS and not
  in OSCAR).
- Tolerance on the control row: 0.1% from 2023-24, 1% before. `pass` inside it; outside it `fail` for BUD
  and `basis difference` for in-year.
- Departmental AME is not compared (it does not reconcile; see the profiling notes).

**audit.bud_inyear_org_match**: every organisation code of the newest in-year release (2026-09) against the
newest BUD vintage's list. Six in-year codes are not in the BUD (`BSR085`, `GBE066`, `IFR048`, `LBC066`,
`LCF048`, `LIL003`, bodies set up after 2024-25). They are reported here with their in-year rows and amounts and
stay in `stg.inyear_snapshot` (**tested**: `sql/tests/409`).

## Results

Runs of 17 November 2026 on the development machine (Windows 11, SQL Server 2022 Developer, Windows
authentication, a scratch database), **tested**. The machine was shared with other builds, so timings vary
a lot between runs; I give two.

| Command | Result |
|---|---|
| `ukfr build --scope full --recreate --yes` | succeeds. Stage `oscar_bud` 129.9 s and 472.0 s in two runs (it reads 15 workbooks of about 33,000 to 40,000 rows and bulk-loads 91 text columns), `oscar_inyear` 155.2 s and 130.7 s, `pss` 4.7 s and 3.5 s, post SQL 75.9 s and 44.6 s |
| `ukfr build --scope committed --recreate --yes` with `UKFR_DATA_DIR` unset | succeeds; none of the files on this page is created (`audit.table_counts` lists none of these tables) and `evidence/build` is byte-identical to git |
| `UKFR_REQUIRE_DB=1 pytest` after the full build | 263 passed |
| `UKFR_REQUIRE_DB=1 pytest` after the committed build, no data directory | 239 passed, 24 skipped (the `localdata` tests) |
| the same files that need the full build, with `UKFR_DATA_DIR` set against the committed database | skipped through `-- requires:` and the `full` fixture, not failed |
| `ukfr control bud`, `ukfr control pss` | rewrite `data/audit/bud_independent_control.csv` (15 rows) and `pss_independent_control.csv` (5 rows) byte for byte (**tested**: `pipeline/tests/test_bud_pss_load.py`) |

**DEL, in-year June release against each BUD vintage** (`audit.bud_vs_inyear_del`, also `evidence/full/`).
All 15 pairs pass at 3.5%; the gap runs from -3.18% (2019-20, 2023-11 vintage) to +3.40% (2023-24, 2024-11
vintage), and 2023-24 against 2025-11 is +3.37%. The 2023-24 pairs sit close to the tolerance.

**PSS against OSCAR, control rows** (`TOTAL EXCL SCOTLAND`, `audit.pss_vs_outturn`):

| Year | Resource DEL excl. depreciation, PSS minus BUD | Capital DEL, PSS minus BUD | Tolerance |
|---|---|---|---|
| 2021-22 | -0.65% (pass) | -0.56% (pass) | 1% |
| 2022-23 | -0.81% (pass) | -0.39% (pass) | 1% |
| 2023-24 | +0.005% (pass) | -0.46% (**fail**) | 0.1% |
| 2024-25 | -0.022% (pass) | -0.36% (**fail**) | 0.1% |

Resource DEL excluding depreciation meets the tolerance in every year. Capital DEL does not meet 0.1% in
2023-24 and 2024-25: PSS is about 0.45bn and 0.37bn below OSCAR, always on the same side. I have not found the
cause; the PSS metadata says it leaves out the security and intelligence agencies and military operations, which
could explain a capital gap, but I did not test that (**designed**, not tested). The failures are in
the table as `fail`, and `sql/tests/412_pss_vs_outturn_controls.sql` pins them to exactly those two rows so a change
is noticed. Against the in-year releases the same rows are `basis difference` for resource DEL in every year
(-1.1% to -2.8%; the in-year files have no ringfence column) and for capital DEL from 2022-23.

**Findings that differ from the profiling pages**

- The profiling comparison of PSS with BUD by group (`pss_vs_bud_by_group.csv`) summed every row of the workbook,
  Closed rows included. The build leaves them out, so a few groups differ by exactly the Closed rows of that group
  and year (**tested**: `test_pss_against_bud_by_group_reproduces_the_profile` checks that the Closed rows
  account for the whole difference).
- `audit.table_counts` counted a columnstore tombstone row group on one run (2,595,654 rows for the
  1,547,078-row in-year table), because `sys.dm_db_partition_stats` still counts it until a background cleanup
  runs. I changed `sql/audit/090_table_counts.sql` to take those rows off.

## Not tested

- That the unexplained capital DEL gap is the security agencies or military operations.
- Anything on a CI runner: the full-scope files need the workbooks, which CI does not have.
- The BUD amounts are all whole numbers; a fractional amount would need the exact-sum helper the in-year load uses
  (the raw column is `DECIMAL(38,10)` and the controls compare exactly).
