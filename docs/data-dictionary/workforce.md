# Data dictionary: departmental workforce (full-time equivalent and paybill)

What `ukfr build --scope full` puts in the database from the departments' monthly workforce management information:
headcount, full-time equivalent and paybill for each organisation, by month, keyed to the organisation dimension's durable
key. What the files hold and what is missing is in [../profiling/workforce.md](../profiling/workforce.md). Every claim here
is labelled **tested** (the test or command) or **designed** (not run).

The files are 20 MB under `$UKFR_DATA_DIR/workforce_mi/` (1,453 files), not in git, so the stage `workforce` and every SQL
object here are scope `full`, and the tests that need the files carry `-- marker: localdata`. CI, which builds the
committed scope, does not run them.

## Decisions

- **Only real numbers are in the fact.** `dw.workforce_month` holds published values and nothing else. The one authored
  input is the map from a published name to an organisation (`authored.workforce_org_map`); it moves a value between
  organisations and adds none. **Tested**: `sql/tests/613_workforce_the_fact_is_the_raw_values_of_mapped_rows_and_nothing_else.sql`
  (the fact's headline totals equal the raw values of the mapped rows, within the 4-decimal rounding),
  `615_workforce_the_map_is_labelled_authored_and_no_other_authored_table_feeds_the_fact.sql`.
- **The grain is the durable organisation key, not the organisation version.** `dw.workforce_month.durable_key` joins to
  `dw.dim_organisation.durable_key`. A later task that wants the version in force in a month joins
  `dw.dim_organisation` on the key and the release range itself; the monthly fact does not carry a version, because a
  release is a quarter and a workforce month is not.
- **One definition of non-payroll people.** `contingent_fte` and `contingent_headcount` count agency, interim, specialist and
  other contingent workers. The older template's "total non-payroll" also counted consultants and is not used (the newer
  template reports consultancy as a number of contracts).
- **A month with two copies uses one.** If a department published a month as csv and as a spreadsheet, every copy is read
  and compared, and the one with the most rows that have a name and a non-zero value counts; on a tie a spreadsheet beats a
  csv (Defra's csv rounds full-time equivalent to whole people). **Tested**: `sql/tests/605_workforce_one_primary_file_per_department_and_month.sql`.
- **Numbers keep 4 decimal places.** A published number is cut to 4 decimal places on the way in (the scale of the fact).
  Spreadsheets store float noise (`41534981.790000454`, or `2.27e-13` where a sum should be 0); at 4 places the file text and
  the spreadsheet library's float give the same number. Raw keeps `decimal(38,10)`, the fact `DECIMAL(19,4)`. Never `float`.
- **Blank is not zero.** A blank cell has no row in `raw.workforce_value`, and no cell of the fact is made up from nothing.
- **Nothing is dropped.** Every row of every primary file is in `dw.workforce_month` or in `quarantine.workforce_row` with
  a reason; every cell that is not a number is in `quarantine.workforce_value`; every file that is not read is on a
  hand-written list with its reason. **Tested**: `610_workforce_every_published_row_is_mapped_or_quarantined_with_a_reason.sql`,
  `604_workforce_every_manifest_file_is_loaded_or_skipped_with_a_reason.sql`.

## Tables

| Table | Rows | Grain |
|---|---|---|
| `raw.workforce_file` | 1,453 | one file; format, header layout, primary or not, `load_status` (1,433 loaded, 20 skipped) |
| `raw.workforce_row` | 17,798 | one non-blank row of a data sheet, the identifying cells as published |
| `raw.workforce_value` | 435,354 | one numeric cell: file, row, column position, the measure key the reader gave the column, the header as published |
| `raw.workforce_ignored_column` | 520 | one comment or note column that is not read |
| `raw.workforce_control_expected` | 52,624 | one file and column: count and sum recomputed by `ukfr.controls.workforce_independent` |
| `quarantine.workforce_value` | 3,554 | one non-blank cell that is not a number |
| `authored.workforce_org_map` | 213 | one published name in one department series (AUTHORED) |
| `stg.workforce_org_map` | 213 | the same, typed, with the name reduced to a key |
| `stg.workforce_row` | 17,798 | one row, with its month and name key |
| `stg.workforce_row_class` | 15,941 | one row of a primary file and what it became (`mapped`, `excluded`, `empty_row`, ...) |
| `dw.dim_workforce_measure` | 15 | one measure of the fact, with its unit and definition |
| `dw.workforce_measure_rule` | 45 | which published columns a measure is read from, in order of preference |
| `dw.workforce_month` | 94,533 | **one durable organisation, month and measure**; 89 organisations |
| `quarantine.workforce_row` | 6,928 | one row of a primary file that is not in the fact, with its reason |
| `audit.workforce_file_control_totals` | 8,600 | one file and headline column: loaded against recomputed |
| `audit.workforce_mapping_coverage` | 1,353 | one department series and month: rows, full-time equivalent and paybill, mapped and not |
| `audit.workforce_department_summary` | 20 | one department series |
| `audit.workforce_row_arithmetic` | 65 | one published row whose total is not the sum of its components |

Counts are from the full build of 2026-11-24 (`ukfr build --scope full --recreate`, 18 minutes). The three audit tables with
rows to commit are in `evidence/full/workforce_*.csv`.

## dw.workforce_month

| Column | Meaning |
|---|---|
| `durable_key` | the organisation, as `dw.dim_organisation.durable_key` |
| `report_month`, `month_start` | the month as `2024-05` and as the first day |
| `measure_key` | a key of `dw.dim_workforce_measure` |
| `value` | `DECIMAL(19,4)`; people for headcount and full-time equivalent, pounds for paybill and cost; credits and corrections can be negative (cost cells only) |
| `source_rows` | published rows behind the cell: the organisation's own row, plus the agencies and parts the map counts in it |
| `rolled_up_rows` | how many of those the map marks `agency_into_parent` or `part_of` |
| `source_priority` | 1 = the file's own total; 2 or 3 = rebuilt from components because the total was blank |
| `publisher` | the department series whose file the cell comes from (one per organisation and month) |

Measures (`dw.dim_workforce_measure`): `payroll_headcount`, `payroll_fte`, `contingent_headcount`, `contingent_fte` (people);
`payroll_paybill_gbp` and its parts `payroll_salary_gbp`, `payroll_allowances_gbp`, `payroll_non_consolidated_gbp`,
`payroll_overtime_gbp`, `payroll_employer_pension_gbp`, `payroll_employer_ni_gbp`; `contingent_labour_cost_gbp`,
`consultancy_cost_gbp`, `non_payroll_cost_gbp`, `staff_cost_total_gbp` (pounds).

**Tested** (`sql/tests/611_workforce_month_grain_and_keys.sql`, `617_workforce_no_negative_people_in_the_fact.sql`): the grain is
unique, every key is in `dw.dim_organisation`, an organisation has one publisher in a month, and no headcount or full-time
equivalent is negative. Negative cells exist only in cost measures (credits and corrections): consultancy 95, contingent
labour 37, non-payroll 50, non-consolidated payments 83, allowances 9, overtime 11, salary 1, total staff cost 1. The
published rows have negative components too (eight cells, HS2's "other" grade and the Pensions Regulator's consultants);
none reaches a headline.

## Months where full-time equivalent and paybill exist

Months of `payroll_fte` and `payroll_paybill_gbp` in the fact, by department series (the publisher of the cells). One month
has a gap when the file for it is missing, could not be read, or has its rows labelled with another month.

| Series | First month | Last month | Months of full-time equivalent | Months of paybill | Organisations |
|---|---|---|---|---|---|
| BEIS | 2018-04 | 2023-08 | 60 | 60 | 10 |
| CMA | 2021-04 | 2026-09 | 66 | 65 | 1 |
| DBT | 2023-07 | 2026-10 | 40 | 40 | 5 |
| DCMS | 2025-01 | 2026-09 | 21 | 21 | 1 |
| Defra | 2018-05 | 2026-09 | 72 | 72 | 11 |
| DESNZ | 2023-09 | 2026-10 | 38 | 37 | 8 |
| DfE | 2018-04 | 2026-10 | 103 | 103 | 11 |
| DfT | 2018-04 | 2026-10 | 102 | 101 | 6 |
| DHSC | 2018-04 | 2026-09 | 102 | 102 | 11 |
| DSIT | 2023-09 | 2026-09 | 37 | 37 | 4 |
| DWP | 2018-04 | 2026-08 | 99 | 97 | 6 |
| FCDO (and FCO) | 2018-04 | 2026-09 | 92 | 91 | 7 |
| FSA | 2021-06 | 2026-10 | 64 | 64 | 1 |
| HMRC | 2018-04 | 2026-10 | 103 | 103 | 1 |
| HM Treasury | 2021-04 | 2026-10 | 24 | 24 | 3 |
| MHCLG (and DLUHC) | 2018-04 | 2026-09 | 99 | 99 | 8 |
| MOD | 2018-04 | 2026-09 | 99 | 99 | 4 |
| NCA | 2025-04 | 2026-10 | 19 | 19 | 1 |
| UK Export Finance | 2018-04 | 2026-08 | 91 | 84 | 1 |

Organisations are durable keys, counted over the whole period; an organisation published by two series at different times
(UKRI under BEIS and then DSIT) is counted in each. **Tested**: `audit.workforce_department_summary`, `dw.workforce_month`
(query in `evidence/full/workforce_department_summary.csv` and the fact).

## The map (authored)

`authored/workforce_org_map.csv` is a table I wrote by hand: 213 rows, one for each published name in each department
series, read against the organisation names in `dw.dim_organisation`. It is not source data.

| Column | Meaning |
|---|---|
| `dept` | the series of the file (`dft`, `defra`, `mod` ...) |
| `organisation_name` | the name as published; matching reduces it (lower case, no punctuation, `&` as `and`), so spelling variants meet |
| `valid_from`, `valid_to` | first and last month the decision covers, empty for open; used where a name means another organisation before and after a date (the FCO and the FCDO) |
| `decision` | `map` or `exclude` |
| `durable_key` | the organisation (`map` only) |
| `basis` | `name` (the same name as the OSCAR organisation, 74 rows), `name_variant` (another spelling, or an earlier or later name of the body, 57), `part_of` (a body that is part of the organisation: the research councils in UKRI, 8), `agency_into_parent` (see below, 44) |
| `reason` | why it is excluded (`exclude` only, 30 rows) |

**`agency_into_parent` is an assumption.** An executive agency (DVLA, Dstl, the Valuation Office Agency ...) has no
organisation of its own in the OSCAR dimension, so I count its people in its parent department's organisation, because the
agency's spending is reported there. I did not check that against the OSCAR lines: it is **designed**. The cells say how many
rows they combine (`rolled_up_rows`), so a reader can remove them.

**Excluded, by decision** (30 rows): bodies with no organisation of their own in the dimension (the British Council, FCDO
Services, NHS Blood and Transplant, the NHS Business Services Authority, NHS Resolution and its earlier names, the
National Infrastructure Commission and a few more); the template's catch-all `OTHER`; total rows; footnote lines; MHCLG's
core department, because OSCAR splits it into two organisations (COM and LGV) and nothing in the file says how to split a
row between them; and HM Land Registry in its own collection, because the BEIS series has it for the same months.

**Tested**: `607_workforce_org_map_rows_are_well_formed.sql` (known series, key exists, reason on every exclusion),
`608_workforce_every_authored_map_row_is_used.sql` (no dead rows), `609_workforce_no_published_name_matches_two_map_rows.sql`.
The README register lists the file.

## Controls

| Control | Result |
|---|---|
| **Per file, per column, against an independent recomputation.** `ukfr.controls.workforce_independent` opens every file with the csv module or `python-calamine`, takes the cells that are numbers and adds them with `Decimal`, and shares no code with the reader. SQL compares the count and exact sum of every column of every loaded file | **Tested**: `sql/tests/600_workforce_loaded_columns_equal_the_independent_recomputation.sql`, `601_...`, `602_workforce_row_counts_equal_the_independent_count.sql`: no difference in any column of any of the 1,433 loaded files (the recomputation has 52,624 file-columns, some of them for files I do not read), and the rows loaded equal the rows counted |
| Headline columns (payroll headcount, payroll and grand total full-time equivalent, contingent full-time equivalent, payroll paybill, grand total paybill) | **Tested**: `audit.workforce_file_control_totals`, 8,600 rows, all `pass`, largest absolute difference 0 (`603_workforce_headline_controls_all_pass.sql`) |
| The reader read the right column | **Tested**: `pipeline/tests/test_workforce_load.py` reads the payroll full-time equivalent total by header text for one csv, one xlsx and one ods file and compares with the loaded sum; `616_workforce_headline_columns_carry_the_published_wording.sql` checks the published header of every headline column |
| Published totals against their components | **Tested** and reported, not corrected: `audit.workforce_row_arithmetic`. 18 rows have a payroll full-time equivalent total more than 1 person away from the sum of its grades, 21 for headcount, 26 for paybill (more than £1,000). Ten of the 18 are DHSC's April and May 2018 files, where the "total" is a small number against grades that sum to thousands. `618_...` pins the counts |
| Mapping coverage (below) | **Tested**: `614_workforce_the_coverage_audit_accounts_for_every_primary_row.sql` |
| The two copies of a month agree | **Tested** by a query on the 80 months with two copies, not a committed test: the full-time equivalent totals differ by at most 0.007% (Defra's csv is rounded to whole people, so it is the one that differs) and the paybill by a few pounds; MOD's two copies are identical |

## Mapping coverage

`audit.workforce_mapping_coverage` (per department series and month) and `audit.workforce_department_summary`. Overall, for
the 9,944 organisation rows of primary files: **9,013 mapped (90.6%)**; by value **93.8% of the published payroll
full-time equivalent** (32.4 million of 34.6 million person-months) and **76.8% of the published payroll paybill**
(£154.5bn of £201.2bn). 5,997 spare template rows are separate (no name, every value zero or blank, nothing in them).

The paybill share is lower than the full-time equivalent share mostly because of MOD: three of its files have rows that say
another month, with about £9bn of paybill in the Ministry of Defence row alone against about £0.17bn in a normal month (I have
not found out why). Those rows are quarantined, so MOD's paybill coverage is 45.5%.

| Series | Months read | Missing | Files | Not read | Templates | Control difference, full-time equivalent | Control difference, paybill | Rows mapped (%) | Full-time equivalent mapped (%) | Paybill mapped (%) |
|---|---|---|---|---|---|---|---|---|---|---|
| BEIS | 60 | 5 | 66 | 6 | no group row, single row | 0 | 0 | 100.0 | 100.0 | 100.0 |
| CMA | 66 | 4 | 68 | 2 | single row | 0 | 0 | 89.2 | 89.3 | 89.6 |
| DBT | 40 | 0 | 40 | 0 | single row | 0 | 0 | 100.0 | 100.0 | 100.0 |
| DCMS | 21 | 0 | 21 | 0 | single row | 0 | 0 | 100.0 | 100.0 | 100.0 |
| Defra | 72 | 29 | 142 | 0 | multi-row, single row | 0 | 0 | 98.9 | 93.0 | 93.5 |
| DESNZ | 38 | 0 | 38 | 0 | single row | 0 | 0 | 100.0 | 100.0 | 100.0 |
| DfE | 103 | 0 | 103 | 0 | multi-row, single row | 0 | 0 | 100.0 | 100.0 | 100.0 |
| DfT | 102 | 1 | 103 | 1 | multi-row, single row | 0 | 0 | 100.0 | 100.0 | 100.0 |
| DHSC | 102 | 0 | 109 | 0 | multi-row, single row | 0 | 0 | 71.3 | 73.0 | 79.5 |
| DSIT | 37 | 0 | 37 | 0 | single row | 0 | 0 | 100.0 | 100.0 | 100.0 |
| DWP | 100 | 1 | 101 | 1 | multi-row, single row | 0 | 0 | 96.8 | 99.0 | 99.0 |
| FCDO | 92 | 10 | 92 | 0 | single row | 0 | 0 | 75.6 | 75.6 | 74.9 |
| FSA | 65 | 0 | 65 | 0 | single row | 0 | 0 | 98.5 | 98.6 | 98.8 |
| HM Land Registry (own collection) | 15 | 5 | 15 | 0 | multi-row | 0 | 0 | 0.0 | 0.0 | 0.0 |
| HMRC | 103 | 0 | 103 | 0 | multi-row, single row | 0 | 0 | 99.0 | 97.9 | 97.5 |
| HM Treasury | 24 | 43 | 24 | 0 | multi-row, single row | 0 | 0 | 92.3 | 99.1 | 98.9 |
| MHCLG | 99 | 3 | 102 | 3 | multi-row, single row | 0 | 0 | 76.9 | 62.2 | 62.2 |
| MOD | 102 | 0 | 105 | 0 | multi-row, single row | 0 | 0 | 96.7 | 97.0 | 45.5 |
| NCA | 19 | 0 | 19 | 0 | single row | 0 | 0 | 100.0 | 100.0 | 100.0 |
| UK Export Finance | 93 | 8 | 100 | 7 | multi-row, single row | 0 | 0 | 97.8 | 97.7 | 97.9 |

The low rows are deliberate: HM Land Registry's own collection is excluded because the BEIS series is the copy I count;
MHCLG's core department is not mapped (above); DHSC and FCDO publish NHS and other bodies that have no organisation of their
own; CMA's gap is the eight carry-over rows of one file.

## What a later task reads

| Object | Grain | Use |
|---|---|---|
| `dw.workforce_month` | durable organisation x month x measure | the pay bridge (paybill change split into volume, rate and organisation mix) and allocation weights |
| `dw.dim_workforce_measure` | measure | unit and definition |
| `dw.workforce_measure_rule` | measure x preference x published column | how a measure is read |
| `quarantine.workforce_row` | published row | what is not in the fact, and why |
| `audit.workforce_mapping_coverage`, `audit.workforce_department_summary` | series x month; series | coverage to show next to a bridge |
| `audit.workforce_row_arithmetic` | published row | cells to annotate or exclude |
| `authored.workforce_org_map` / `stg.workforce_org_map` | published name | the decisions behind the keys |

## Limitations

- **No grade-mix effect**: paybill is not split by grade (see the profile).
- **Rolled-up agencies**: counted in the parent organisation by assumption; filter on `rolled_up_rows` to see the organisation
  on its own rows.
- **Months the fact lacks**: gaps listed in the profile; a file labelled with another month is quarantined, not moved.
- **Key, not version**: the fact is by durable key; where a body changed department in the period, the department it sat in
  is the one of the version you join.
- **Not the whole of government**: no Home Office, Ministry of Justice, Cabinet Office or ONS in the source.
