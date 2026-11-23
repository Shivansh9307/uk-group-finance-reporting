# Data dictionary: in-year outturn, dimensions and the revision-delta fact

The conformed dimensions for in-year outturn and `dw.fact_outturn`, which stores revision deltas rather
than stacked snapshots. Built by `ukfr build --scope committed` from the 31 in-year releases, the
organisation and department dimensions, and one authored file. Every claim is labelled **tested** (the
command and where the result is) or **designed**. Amounts are GBP thousands, spending positive, income
negative, `DECIMAL(19,4)`.

Everything here is real data. The one authored input, `authored/account_flow.csv`, decides whether an
economic category is expenditure or income; it never touches an amount (**tested**:
`sql/tests/312_dimension_rows_are_complete_and_labelled.sql`, and `200_authored_tables_are_labelled.sql`
for the table description).

## Tables

Counts are from `evidence/build/table_counts.csv`, written by the build.

| Table | Rows | Grain |
|---|---|---|
| `dw.dim_release` | 31 | one in-year release |
| `dw.dim_period` | 143 | financial year x period 0-12, FY2018-19 to FY2028-29 |
| `dw.dim_scenario` | 5 | one scenario |
| `dw.dim_account` | 128 | one economic category code, plus Unknown |
| `dw.dim_control_budget` | 6 | one control budget detail code, plus Unknown |
| `dw.dim_segment` | 3,766 | one sub-segment code, plus Unknown |
| `dw.dq_issue` | 9 | one data-quality finding |
| `dw.fact_outturn` | 658,554 | release x line, only non-zero deltas |
| `stg.outturn_line_snapshot` | 1,328,928 | release x line, what each release reports, on warehouse keys |
| `stg.account_flow` | 12 | typed `authored.account_flow` |
| `raw.profile_inyear_delta_rowcount` | 31 | the profiled delta row count per release, landed as written |
| `audit.delta_invariant` | 31 | one release |
| `audit.delta_rowcount` | 31 | one release |

`dim_organisation` and `dim_department` are described in [organisation.md](organisation.md).

## The fact: dw.fact_outturn

A **line** is (organisation_key, segment_key, account_key, control_budget_key, period_key). `period_key`
carries the financial year, so a line never spans two years. Each in-year release reports exactly one
financial year to date, so for release R and a line:

    delta = amount in R - amount in the previous release of the same financial year   (0 if absent there)

and only non-zero deltas are stored. A line reported before and absent in R gets a negative delta that
reverses it. "As at release R" is `SUM(amount_delta)` over releases up to R for R's financial year, and it
equals what R reports.

| Column | Meaning |
|---|---|
| `release_key` | `dw.dim_release`, equal to the release sequence |
| `organisation_key` | `dw.dim_organisation`, the version the release used |
| `department_key` | the department as that release reports it |
| `current_department_key` | the department in the current structure, from `stg.current_structure_map` (`-1` where the map has no row) |
| `segment_key`, `account_key`, `control_budget_key`, `period_key` | the dimensions below |
| `scenario_key` | always 1, Outturn |
| `amount_delta` | `DECIMAL(19,4)`, never zero |
| `revision_no` | 0 on the first delta row of a line, then 1, 2, 3 (the largest is 3). "As first reported" is `revision_no = 0` |
| `dq_issue_id` | the unit-error finding the row belongs to (the unit error or its offsetting line), else NULL |

Clustered columnstore index. There are no foreign key constraints: the dimension files are rebuilt by
earlier files in the same run, and a test proves every key resolves instead.

Decisions:

- **Deltas are computed on warehouse keys**, taken from `dw.organisation_release_map`, not on source
  codes. A line whose organisation version changes between two releases of one year is minus under the old
  key and plus under the new key. That is intended, and it is what makes the as-at amount equal what the
  release reports across a Type 2 change.
- **Zero means absent.** The stage already drops exact zeros; 58 float-residue rows round to `0.0000` and
  are removed when the line snapshot is built (1,328,986 staged rows, 1,328,928 line rows).
- **Economic budget is an attribute of the account, not part of the key.** Its relabel from `NA` to
  `OTHER NON-BUDGET` in 2022 therefore produces no vanish-and-appear pair. The control budget is an
  attribute of the control budget detail code.
- **One department per line.** A line carries the same department in every release that reports it
  (**tested**: `311_*`). The only code that is reported under two departments in one release, EHR030 (one row), is a
  different line from the code it merges into, so no line is ever split.
- **Period 0.** The 71 June 2019 rows labelled "Period 0" are in the fact as period 0 of FY2018-19, once,
  and in the year total (**tested**: `307_*`, `pipeline/tests/test_outturn_fact.py`).

### How the SQL builds it

`dw/310_outturn_line_snapshot.sql` joins each staged row to the release map and the dimensions and sums
to line grain (no source line needed summing, 0 groups had more than one row). `dw/330_fact_outturn.sql`
adds each snapshot row to its own release and subtracts it from the next release of the same financial
year, then keeps the non-zero sums. `ROW_NUMBER` over the line gives `revision_no`.

The cost: the dimension and fact files add about 60 seconds of SQL to the build (**tested**, see
Results).

## Dimensions

### dw.dim_release

`release_key` equals `release_seq` (1 = March 2019, in publication order). Columns: `label` (`2024-06`),
`display_label` (`Jun 2024`), `financial_year`, `first_published`, `highest_period` (3, 6, 9 or 12),
`release_in_year` (0 for the first release of a year), `version_label`, `is_latest_release`,
`is_year_end_release` (covers period 12: June releases, 8 of the 31).

### dw.dim_period

`period_key` is `yyyypp`, with `yyyy` the year the financial year starts in: `202204` is April 2022,
`201800` is period 0 of FY2018-19. 13 rows for each of 11 years (**tested**: `307_*`). Period 0 means
"not allocated to a month": `month_start_date` and `fiscal_quarter` are NULL, `is_period0` is 1, and it
is counted in year totals and year to date. The source has period 0 only in June 2019, so the fact has
period 0 only for FY2018-19. Years to 2028-29 are there because plans run that far.

### dw.dim_scenario

| Key | Scenario | Derived | What it is |
|---|---|---|---|
| 1 | Outturn | no | what departments reported, month by month, in each in-year release (this fact) |
| 2 | Plan | no | the annual budget as published |
| 3 | Plan (phased) | yes | the annual plan spread over months by a stated rule |
| 4 | Departments' forecast | no | the monthly forecast departments sent to HM Treasury |
| 5 | Own forecast | yes | a forecast built in the warehouse; never mixed into the others |

Only Outturn is filled by this fact. The rows are static.

### dw.dim_account

One row per economic category, taken from the latest release that reports it. 127 categories plus
Unknown. Columns: `economic_category_code`, `economic_category_name`, `economic_category_label`,
`pesa_economic_group_code`, `pesa_economic_group` (the long name exists only in the 2019 layout, so it is
read from any release that has it), `economic_budget`, `flow`, `flow_basis`, `source_codes`,
`first_release`, `last_release`.

- **`n/a` and `NA` are one member.** The code is `n/a` from 2019-03 to 2021-06 and `NA` from 2021-09. Both
  are named n/a, both have PESA group n/a, and they never appear in the same release, so the dimension has
  the member `NA` and `source_codes` says `NA | n/a`. This is why there are 127 categories, not the 128
  distinct codes in the files. It is my choice; a row per spelling would also have worked.
- **Income or expenditure (`flow`).** Sign does not settle it: 125 of 128 category codes carry both signs.
  The rule is the final digit of the code (1 is Expenditure, 2 is Income, which holds for 116 of 125
  categories on net sign in the profile) with `authored/account_flow.csv` for the 12 codes where it does
  not decide or where net sign and digit disagree. `flow_basis` says `authored` or `digit rule`. A code
  with any other final digit and no authored row stops the build. 115 categories use the digit rule, 12
  are authored (**tested**: `308_*`). I am less sure of two of the authored rows (R501, M102): the name
  does not say which way the account runs, so those are the digit rule alone, and the file says so.
- **Economic budget** is the latest release's value. It is one value per category in the data, except the
  NA category (**tested**: `308_*`).

### dw.dim_control_budget

Five detail codes plus Unknown. `control_budget` is DEL, AME or Non-budget: the published control budget
with a leading `TOTAL ` removed (it is `TOTAL DEL` from December 2022). The build stops if a detail code
has more than one normalised value (**tested**: `312_*`). `published_labels` lists the published values
(`DEL | TOTAL DEL`), and `control_budget_detail` is my display name for the detail code.

### dw.dim_segment

One row per sub-segment code with a non-zero row (3,765, plus Unknown); 47 codes that carry only zero rows
have no fact rows and no member. `segment_name` is the name in the latest release that reports the code
(a code has one name in a release: **tested**, `312_*`), `segment_label` the same without the leading
`CODE-`. The code `x017A064` (2019-03 to 2021-06) is spelled `X017A064` from 2020-12; the database
compares codes case insensitively, so it is one segment and its line continues across the change.

## Data quality: dw.dq_issue

Nine findings, each found by a SQL rule (never a hard-coded key). Only rule a flags fact rows.

| Rule | Finding | Rows |
|---|---|---|
| a | A line whose amount exceeds GBP 1bn in one of two consecutive releases of a year, with the same sign and a factor between 900 and 1,100 between them (issue type `unit error`); and a line of the same organisation, category, control budget and month whose change between the same two releases is the opposite of that line's change within 1% (`unit error (offsetting line)`) | 6 findings: NHS Pension Scheme `X903A002` (unit error) and `X903A003` (offsetting line), each for April 2023 and May 2023 in 2023-09 to 2023-12, and April 2025 in 2025-12 to 2026-03 |
| b | Quarter column disagrees with Month, read from raw | 2022-09, all 23,787 rows |
| c | Period 0 rows | 2019-06, 71 rows, GBP 269,890 thousand net |
| d | Second spelling of a code in one release, from the authored `coding_error` override | EHR030 in 2019-06 |

Rule a flags thirteen fact rows: for each finding, the delta rows of the line-month from the row that set
the wrong amount (the delta row of largest absolute size at or before the first release of the pair) to the row that
corrected it. That is six rows on `X903A002` and seven on `X903A003` (the offsetting line also has a small revision in
December 2025 between the two). A sign test keeps out the one other line that changes by a factor near 1,000: HMRC
`X041A094` for September 2021, from -1,811 in 2021-12 to 1,890,000 in 2022-03, which is a real change with a different
sign. The offsetting line is found from the unit error, not from its own factor: it keeps a genuine amount after the
correction, so its change is a factor of 125 to 833. The rule cannot see an error that is not corrected in the next
release or that first appears already wrong. **Tested**: `309_*`, `310_*` and `762_*`.

## Audits

`audit.delta_invariant` (`evidence/build/delta_invariant.csv`): for each release, the staged snapshot
total, the as-at total from the deltas, their difference, and `amount_sum_rounded_4dp` from the control
table. All 31 releases pass with a difference of exactly zero (**tested**: `300_*` at full grain, `301_*`
by department, `302_*` in total).

| Release | Snapshot total | As at from deltas | Difference | Control total |
|---|---|---|---|---|
| 2019-03 | 639,865,659 | 639,865,659 | 0 | 639,865,659 |
| 2019-06 | 749,955,441 | 749,955,441 | 0 | 749,955,441 |
| 2019-09 | 217,108,691 | 217,108,691 | 0 | 217,108,691 |
| 2019-12 | 429,067,186 | 429,067,186 | 0 | 429,067,186 |
| 2020-03 | 661,561,387 | 661,561,387 | 0 | 661,561,387 |
| 2020-06 | 968,856,707 | 968,856,707 | 0 | 968,856,707 |
| 2020-09 | 243,126,768 | 243,126,768 | 0 | 243,126,768 |
| 2020-12 | 547,368,425 | 547,368,425 | 0 | 547,368,425 |
| 2021-03 | 792,074,925 | 792,074,925 | 0 | 792,074,925 |
| 2021-06 | 1,139,607,242 | 1,139,607,242 | 0 | 1,139,607,242 |
| 2021-09 | 288,911,755 | 288,911,755 | 0 | 288,911,755 |
| 2021-12 | 490,978,103 | 490,978,103 | 0 | 490,978,103 |
| 2022-03 | 862,315,480 | 862,315,480 | 0 | 862,315,480 |
| 2022-06 | 1,236,285,677 | 1,236,285,677 | 0 | 1,236,285,677 |
| 2022-09 | 296,221,382 | 296,221,382 | 0 | 296,221,382 |
| 2022-12 | 594,595,031 | 594,595,031 | 0 | 594,595,031 |
| 2023-03 | 776,968,996.6818 | 776,968,996.6818 | 0 | 776,968,996.6818 |
| 2023-06 | 1,006,364,326.5456 | 1,006,364,326.5456 | 0 | 1,006,364,326.5456 |
| 2023-09 | 321,042,336.968 | 321,042,336.968 | 0 | 321,042,336.968 |
| 2023-12 | 595,982,430.6276 | 595,982,430.6276 | 0 | 595,982,430.6276 |
| 2024-03 | 864,797,648.4134 | 864,797,648.4134 | 0 | 864,797,648.4134 |
| 2024-06 | 1,160,485,035.6297 | 1,160,485,035.6297 | 0 | 1,160,485,035.6297 |
| 2024-09 | 298,954,255.9377 | 298,954,255.9377 | 0 | 298,954,255.9377 |
| 2024-12 | 590,415,231.0556 | 590,415,231.0556 | 0 | 590,415,231.0556 |
| 2025-03 | 926,032,252.4577 | 926,032,252.4577 | 0 | 926,032,252.4577 |
| 2025-06 | 1,227,863,150 | 1,227,863,150 | 0 | 1,227,863,150 |
| 2025-09 | 304,456,382 | 304,456,382 | 0 | 304,456,382 |
| 2025-12 | 601,377,508 | 601,377,508 | 0 | 601,377,508 |
| 2026-03 | 946,817,223.6394 | 946,817,223.6394 | 0 | 946,817,223.6394 |
| 2026-06 | 1,293,643,283.2744 | 1,293,643,283.2744 | 0 | 1,293,643,283.2744 |
| 2026-09 | 315,592,703.9863 | 315,592,703.9863 | 0 | 315,592,703.9863 |

`audit.delta_rowcount` (`evidence/build/delta_rowcount.csv`) compares the delta rows per release with the
profile's count (`docs/profiling/data/inyear_delta_rowcount.csv`, 649,475 in total). The fact has 658,554
rows, 9,079 more. Every difference has a reason and the reasons add up (**tested**: `313_*`):

| Reason | Rows | Releases |
|---|---|---|
| An organisation version changes inside a financial year: minus under the old key, plus under the new one | +10,749 | 2020-03, 2020-12, 2021-06, 2021-12, 2022-03, 2024-12, 2025-03, 2025-06, 2026-06 |
| An exact change under 0.0001 (float residue) rounds to a zero delta at four decimals, so no row is stored | -1,652 | 2023-03 onwards; 1,600 of them in 2026-06 |
| A sub-segment code that only changes letter case (`x017A064`) is one line here and a vanish-and-appear pair in the profile | -18 | 2020-12 (6), 2021-03 (12) |

649,475 + 10,749 - 1,652 - 18 = 658,554. The profile's count is also recomputed in SQL from
`raw.oscar_inyear` with exact amounts and case-sensitive codes, a method that shares nothing with the
fact build, and it agrees with the profile in every release (`profile_diff_rows` is 0).

The per-release table is in `evidence/build/delta_rowcount.csv`.

## Tests

All in `sql/tests/` (prefix 300 to 313), run by `pipeline/tests/test_sql_invariants.py`, plus
`pipeline/tests/test_outturn_fact.py`.

| Test | What it proves |
|---|---|
| 300 | for every release, deltas up to it equal its snapshot on every line, and are zero for lines it does not report |
| 301 | the same by department as reported |
| 302 | the as-at total equals `amount_sum_rounded_4dp`; `audit.delta_invariant` passes |
| 303 | a release's deltas never touch another financial year |
| 304 | no NULL or orphan key, none resolves to Unknown, no zero amount |
| 305 | five dimensions have exactly one Unknown member |
| 306 | `revision_no = 0` rows are exactly the lines ever reported (595,004), each with its first reported value; revisions run 0, 1, 2 in release order |
| 307 | 13 periods per year for 11 years; period 0 in the fact only for FY2018-19 |
| 308 | every category has one economic budget and one flow |
| 309 | rule a flags the NHS Pension Scheme lines and nothing else; the flagged fact rows are the right ones |
| 310 | rules b, c and d match raw and the authored file |
| 311 | one department per line; `current_department_key` follows the map |
| 312 | dimension contents, scenario rows, column type, columnstore index, no amount in the authored table |
| 313 | row counts agree with the profile; every difference is explained |

I proved that tests 300, 301, 302, 306 and 309 fail when I change a fact row by hand, so they are not
vacuous (**tested** once, by hand, against the built database).

## Results

Local figures on 17 November 2026 (SQL Server 2022 Developer, Windows
authentication, a scratch database), **tested**:

| Command | Result |
|---|---|
| `ukfr build --scope committed --recreate --yes` | succeeds; post SQL 73.2 s in the last build, against 27.0 s for the same build on `main` before this change, so the files added here take about 45 s (the builds I ran varied between 73 and 94 s of post SQL); total 3 min 25 s, of which the in-year load stage is 129.6 s |
| `pytest` with `UKFR_REQUIRE_DB=1` | 259 passed, 24 skipped in 39 s (the skips need files under `UKFR_DATA_DIR`, which I did not set) |
| `ruff check pipeline` | all checks passed |

## Not in this layer

No plan, annual or forecast rows. `dw.fact_outturn` carries Outturn only; the annual restated fact is
`dw.fact_outturn_annual` ([annual-restated.md](annual-restated.md)). The current-structure mapping behind
`current_department_key` is the default rule in `stg.current_structure_map` and is replaced by a later
task with the same columns.
