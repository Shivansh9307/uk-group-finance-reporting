# Reconciliation: from the published file to the warehouse

This page shows, for each source, the chain from the file the publisher released to the table the model will
read, the control on every link, the tolerance, the test or audit file that checks it and the result. It also
lists the differences that I could not close. They are published here and in the evidence files, not hidden.

Every result is labelled **tested** (with the command and the file the result is in) or **designed** (not run).
A figure is quoted from an evidence file or from a query I ran against the built database; where a figure I had
written down earlier disagreed with the evidence, the evidence won and the page says so.

## How the checks are run

| Build | Command | What it loads | Runs where |
|---|---|---|---|
| committed scope | `uv run --project pipeline ukfr build --scope committed --recreate --yes` | the 31 OSCAR in-year releases and the Estimates and PESA workbooks, all in git | CI job `pipeline-sql`, and locally |
| full scope | `UKFR_DATA_DIR=<folder holding the larger files> uv run --project pipeline ukfr build --scope full --recreate --yes` | the above plus the annual restated files (BUD), the PSS database and the OSCAR Plans | locally only: the larger files are not in git |

Each build is followed by `UKFR_REQUIRE_DB=1 uv run --project pipeline pytest`, which runs every assertion in
the appendix against the built database. `UKFR_REQUIRE_DB=1` turns a database test that cannot run into a
failure. In a committed-scope database the assertions whose scope is full are skipped, because the tables they
read are not built; in a full-scope database none is skipped.

**Tested** (local runs on 18 November 2026, Windows 11, SQL Server 2022 Developer, Windows authentication):

| Command | Result |
|---|---|
| `ukfr fetch --verify` | 48 committed files ok, 0 failures |
| `ukfr build --scope committed --recreate --yes` into a scratch database | succeeds in 3 min 13 s wall clock: stage `oscar_inyear` 107.9 s, post SQL 81.9 s, the rest 2.5 s |
| `UKFR_REQUIRE_DB=1 pytest`, committed-scope database | 311 passed, 30 skipped in 37.2 s. The 30 skips are the assertions of scope full (`localdata` or `requires`) |
| `ukfr build --scope full --recreate --yes` | succeeds in 9 min 33 s wall clock: stage `oscar_bud` 130.6 s, `oscar_inyear` 106.2 s, `plans_oscar` 171.4 s, post SQL 158.8 s, the other stages 4.6 s |
| `UKFR_REQUIRE_DB=1 pytest`, full-scope database | 341 passed, 0 skipped in 83.6 s |

The machine was quiet for both timed builds: before each I checked that no other `ukfr` process was running and the
processor was at 2 to 7% (the builds used the local SQL Server instance, nothing else of mine was running). Earlier
full builds on this machine took 11 to 24 minutes under load; 9 min 33 s is what a quiet machine gave. The full-scope
results are committed as `evidence/full/build_summary.csv` (seconds per step and rows loaded per stage),
`evidence/full/pytest_summary.csv` and `evidence/full/table_counts.csv`, written by `ukfr build-summary`, which
refuses a log with a local path or user name and a test run with a skip or a failure.

### What CI runs, and what it does not

The workflow is `.github/workflows/ci.yml`. The job `pipeline-sql` (Ubuntu runner, SQL Server 2022 container,
SQL authentication) is the one that proves the pipeline: it verifies the committed files against the manifest,
runs the database-free tests, lists every assertion (`ukfr inventory`), builds the committed scope, runs every
database test, rebuilds into a second database and compares the audit output byte for byte with the first and
with `evidence/build`, and then runs the negative control below. It has no fixture or spike step left.

The job `model-bpa` runs on the real model with the project rule file `te/bpa/rules.json` and compares the result with
`evidence/bpa` (see [te/bpa/README.md](../te/bpa/README.md)); it proves the rules and the count check, and says nothing about the
numbers in the model, which the DAX tests check on my machine. The job `report-checks` runs the rules of `tests/report` on the real report
(`model/UKGroupFinance.Report`): at most thirty data visuals on a page, no image or map visuals, and alt text on every visual. It keeps a
negative control (a limit of one data visual per page) that must fail. It proves nothing about the numbers on the pages, which
`evidence/report/screenshot_figures.csv` and the DAX tests cover.

**Not run in CI (designed, not run there):** the full-scope build and the assertions that need it, because the
annual extracts and workbooks are about 620 MB and are not in git. They run locally; the results are the ones
above and the evidence under `evidence/full/`.

### The negative control

A green run of the controls is only worth something if the controls would have been red on a wrong number.
The last step of `pipeline-sql` (`ukfr negative-control`, `pipeline/src/ukfr/negative_control.py`) therefore
plants three errors, one at a time, in the second, throwaway database (never the one the tests ran against, and it
refuses to touch the default database name), runs the controls that must notice in their own pytest process and
requires each to fail, then puts the original value back and requires them to pass again:

| Planted error | Controls that must fail |
|---|---|
| the control total of one release is 1 (GBP thousand) too high | `sql/tests/004` (staged sum equals the control), `sql/tests/302` (deltas equal the control total) |
| one raw source amount is 1 too high | `sql/tests/003` (raw exact sum equals the control sum) |
| one revision delta of `dw.fact_outturn` is 1 too high | `sql/tests/302`, and `pipeline/tests/test_real_totals.py` (the pinned row count and sum of the real fact) |

The step is green only if every planted error was caught and every restore is clean; afterwards it checks that
`git status` shows no change, so no committed file was touched. **Tested** locally and in CI:

| Where | Result |
|---|---|
| local, `ukfr negative-control` against a scratch database built from the committed files (32 s) | all three plants caught (`caught` for `sql/tests/003`, `004`, `302` and `test_real_totals`), each restore clean (`pytest exit code 0`); exit code 0 |
| CI, run [44256921066](https://github.com/Shivansh9307/uk-group-finance-reporting/actions/runs/44256921066), step "Negative control" (15.2 s) | the same lines in the job log; the step and the job are green |

If a control were broken, for example a test whose query could no longer return a row, the first run for that plant
would not list the test as failed, the command would print `NOT CAUGHT: <test id>` for it and exit 1, and the CI
step and job would be red. I checked that the step goes red for a broken control by running it against a database
where the planted value was already corrected before the check: **tested**, twice. Locally I added `WHERE 1 = 0 AND` to `sql/tests/003` and ran the command: it printed
`NOT CAUGHT: ...test_invariant[003_raw_exact_sum_equals_file_sum.sql]`, `expected pytest exit code 1 with the error
planted, got 0` and `negative control FAILED`, and exited 1; the other two plants were still caught. In CI I pushed
the same change as a temporary commit (run
[44258121672](https://github.com/Shivansh9307/uk-group-finance-reporting/actions/runs/44258121672)): the database
tests step stayed green, because the blinded test passes, the negative control step printed `NOT CAUGHT` and failed,
and the job failed. I then removed the commit from the branch (reset and force-push to my own branch), so the pull
request holds one coherent change.

## The chain, source by source

In every table below, GBP amounts are thousands, as OSCAR publishes them.

### 1. OSCAR in-year releases (31 releases, committed scope)

| Link | Control and tolerance | Test or audit file | Result |
|---|---|---|---|
| published file to the committed copy | sha256 equals `data/manifest/files.csv`; exact | `ukfr fetch --verify`; `sql/tests/010_file_hashes_match.sql`; `audit.file_control.sha256_status` | **tested**: 32 of 32 files pass (`evidence/build/file_control.csv`) |
| file to `raw.oscar_inyear`: rows | rows read equal the rows in the control file `data/audit/inyear_file_control_totals.csv`, and loaded plus quarantined equal read; exact | `sql/tests/002`, `009`, `015` | **tested**: 1,547,078 rows in the 31 primary files, none quarantined |
| the same: amounts | the exact raw sum (up to 31 decimals) equals the control sum; tolerance 0 for CSV. A second control, `ukfr control inyear`, recomputes rows and sums with no code from the readers (`data/audit/inyear_independent_control.csv`); ODS files may differ by float residue (1e-6) | `sql/tests/003`; `pipeline/tests/test_independent_control.py` | **tested**: 31 of 31 pass |
| raw to `stg.inyear_snapshot`: zero rows and precision | staged rows equal data rows minus zero rows; the staged sum (`DECIMAL(19,4)`) equals `amount_sum_rounded_4dp`; tolerance 0. Rounding to four decimals moves a file total by at most 0.0054 (GBP 5.44, release 2024-06); both sums are in `audit.file_control` | `sql/tests/004`, `005`, `014` | **tested**: 31 of 31 pass; no `float` or `real` column in the database |
| snapshot to `dw.fact_outturn` | for every release, the sum of the revision deltas up to it for its financial year equals that release's control total, in total, by department and at full grain; tolerance 0 | `sql/tests/300`, `301`, `302`; `audit.delta_invariant` | **tested**: 31 of 31 releases, difference exactly 0 (`evidence/build/delta_invariant.csv`) |
| fact rows against the profile | 658,554 fact rows against 649,475 non-zero changes in the profile; every difference is explained (+10,749 key changes inside a year, -1,652 changes below 0.0001, -18 case-only sub-segment codes) | `sql/tests/313` | **tested** |
| the real fact is not touched by anything derived | row count and sum of `dw.fact_outturn` pinned: 658,554 rows, 9,098,653,566.4360 | `pipeline/tests/test_real_totals.py`, `evidence/expected/real_fact_totals.csv` | **tested** |

Source errors are reported, not corrected. `dw.dq_issue` has nine findings: three unit errors on the NHS Pension
Scheme line `X903A002` (a 1,000 times too large amount in one release, corrected in the next: April and May 2023,
and April 2025), the same three line-months of its offsetting line `X903A003`, all 23,787 rows of September 2022 with the wrong quarter, the 71 period-0 rows of June 2019
(GBP 269,890 thousand net, kept as period 0) and the double spelling of the code `EHR030` in June 2019. The unit
errors and the offsetting line flag thirteen fact rows (six and seven), so a gross-restatement view can leave them out. **Tested**: `sql/tests/309`, `310`
(`dw.dq_issue`; `docs/data-dictionary/outturn.md`). An earlier note of mine spoke of two such lines; the rule
finds three findings on each of two lines.

### 2. Annual restated files, BUD (full scope)

| Link | Control and tolerance | Test or audit file | Result |
|---|---|---|---|
| workbook to `raw.oscar_bud`: rows and sums | rows and the sum of all rows equal the control file `data/audit/bud_file_control_totals.csv` and the independent recomputation `data/audit/bud_independent_control.csv`; exact | `sql/tests/400`, `401`; `audit.bud_file_control` | **tested**: 15 of 15 workbooks pass (`evidence/full/bud_file_control.csv`) |
| raw to `dw.fact_outturn_annual` | the fact equals the raw sum with the `Closed` rows left out (every duplicate is a `Closed` row); tolerance 0 | `sql/tests/404`, `405` | **tested** |
| BUD against the in-year releases | DEL at total level, 15 financial-year and vintage pairs, tolerance 3.5% of the BUD amount | `sql/tests/408`; `audit.bud_vs_inyear_del` | **tested**: 15 of 15 pass; the gap runs from -3.18% (2019-20, vintage 2023-11) to +3.40% (2023-24, vintage 2024-11) (`evidence/full/bud_vs_inyear_del.csv`) |
| the same, AME, non-budget and total | no tolerance: the restated files carry layers the in-year files do not | `audit.bud_vs_inyear_del` | **recorded, not tested**: the status is `boundary difference` for all 45 rows, by design |

The in-year files lack the ringfence column, so a monthly plan variance from in-year data carries a basis note;
the exact basis is used wherever the annual file exists.

### 3. Public Spending Statistics (PSS), the independent control (full scope)

| Link | Control and tolerance | Test or audit file | Result |
|---|---|---|---|
| PSS database to `raw.pss` | rows and sums equal `data/audit/pss_file_control_totals.csv` and the independent recomputation | `sql/tests/410` | **tested** |
| PSS against the annual outturn, DEL, excluding Scotland | resource DEL excluding depreciation and capital DEL by year; tolerance 1% to 2022-23 and 0.1% from 2023-24 | `sql/tests/412`; `audit.pss_vs_outturn` | **tested**: resource DEL passes in all four years; capital DEL passes in 2021-22 and 2022-23 and fails in 2023-24 (-0.46%) and 2024-25 (-0.36%), see the residuals below (`evidence/full/pss_vs_outturn.csv`) |
| PSS against the in-year releases | the same measures | `audit.pss_vs_outturn` | **recorded, not tested**: 9 of 10 rows are `basis difference` (-0.7% to -2.8%); the in-year files cannot leave out ringfenced items |

### 4. OSCAR Plans, FY2017-18 to FY2021-22 (full scope)

| Link | Control and tolerance | Test or audit file | Result |
|---|---|---|---|
| extract to `raw.plan_oscar` | rows read per extract equal `plans_rows` in `data/audit/extract_file_control_totals.csv`; exact | `sql/tests/520` | **tested** |
| raw to `dw.fact_plan` grain A | the grain A total of each year equals the raw rows and `stg.plan_oscar`; grain: organisation x control budget detail x economic budget; tolerance 0 | `sql/tests/521`, `522` | **tested** |

### 5. Estimates DEL (committed scope)

| Link | Control and tolerance | Test or audit file | Result |
|---|---|---|---|
| sheet to staging | for each section and year, the published total equals the sum of the lines above it, within (lines + 1) x half a unit of the last published digit | `sql/tests/501`; `audit.plan_sheet_control` | **tested**: 27 of 27 Estimates sheet-years pass (`evidence/build/plan_sheet_control.csv`) |
| staging to `dw.fact_plan` grains B and C | the fact total equals the final-plan Estimates lines; tolerance 0 | `sql/tests/509`, `512` | **tested** |
| Estimates 2026-27 against PESA 2026 | the Main Estimate equals the PESA plan, group by group, after the Budget Exchange adjustment | `sql/tests/537` | **tested** |
| FY2023-24 figures against the profiling | Estimates plan, PESA plan and PESA outturn reproduced to the thousand pound | `pipeline/tests/test_plans_sql.py::test_fy2023_24_consistency_figures_are_reproduced` | **tested** |

### 6. PESA and Spending Review 2025 tables (committed scope)

| Link | Control and tolerance | Test or audit file | Result |
|---|---|---|---|
| sheet to staging | the same section-and-year control as for the Estimates; unrounded SR25 tables to 9 places | `sql/tests/501`; `audit.plan_sheet_control` | **tested**: 355 of 355 sections with a total pass; 2 capital AME sections have no 2029-30 total and are listed as `no total` |
| staging to `dw.fact_plan` grain D | the latest PESA edition that still calls the year `plans`, one per year and kind of budget | `sql/tests/508`, `510` | **tested** |

### 7. Current structure of departments (committed scope; hold-out in full scope)

| Link | Control and tolerance | Test or audit file | Result |
|---|---|---|---|
| every outturn line has one current department | exactly one row per organisation version and sub-segment; never Unknown or closed | `sql/tests/450`, `311` | **tested**: 5,480 pairs |
| the map moves lines, not amounts | the current-structure totals equal the reported and the snapshot totals; tolerance 0 | `sql/tests/452` | **tested** |
| hold-out against the 2025 annual file | the in-year outturn on the current structure against the annual file that was not used to build or review the map, by year, level and department | `sql/tests/455`; `audit.current_structure_holdout` | **recorded, not tested for a tolerance**: the table adds up to `audit.bud_vs_inyear_del`; the residuals are published (below) |

### 8. Bridge, phasing and outturn on the plan's basis (committed scope; annual basis in full scope)

| Link | Control and tolerance | Test or audit file | Result |
|---|---|---|---|
| outturn lines to Spending Review groups | every pair has exactly one group, none through an unknown department, none in a plan-side member; the regrouped lines add up to the fact in total and in every release; tolerance 0 | `sql/tests/550`, `551` | **tested** |
| bridge against the BUD's own groups | 255 of 283 organisation codes agree; the 31 differing rows are the ones pinned | `sql/tests/561` (full scope) | **tested**: the differences are intended (the bridge follows the current structure) |
| phasing profile | twelve shares per plan row add up to exactly 1; the method of every profile is recomputed without the profile code | `sql/tests/552`, `553`, `554` | **tested** |
| phased plan | the twelve months add up to the annual plan exactly | `sql/tests/555` | **tested** |
| in-year outturn on the plan's basis | recomputed from `dw.fact_outturn` for every release, group and measure | `sql/tests/556` | **tested** |
| in-year against annual outturn on the plan's basis | none passes or fails: the in-year files lack the ringfence column | `audit.plan_basis_inyear_vs_annual` | **recorded, not tested**: see the FY2023-24 gaps below |
| nothing derived reaches a real total | the real facts keep their pinned row counts and sums; the phased plan is flagged derived and nothing reads it | `pipeline/tests/test_real_totals.py`, `sql/tests/558` | **tested** |
| FY2022-23 outturn of BEIS, DCMS and DIT in the group the plan is published under | the outturn of the departments 013, 048 and 084 as reported is in the combined group, nowhere else is regrouped, the group has an outturn wherever it has a plan | `sql/tests/800` | **tested** (full build): the old logic left the group with a plan and no outturn (four cells) |
| annual outturn on the plan's basis holds departmental AME | every vintage and year adds up to the control budget detail DEPT AME of the annual file | `sql/tests/801` (full scope) | **tested** |
| every plan variance from FY2022-23 has a verdict | the audit ties to `dw.fact_plan` and to the in-year plan-basis table, the gaps add up, the unexplained cells are the seven pinned | `sql/tests/802`, `803`, `804` (full scope) | **tested**; see section 9 |

### 9. Plan variance reconciliation (full scope)

The first version of the report led with a plan variance of -8.5% in 2025-26 (-110.24bn). That was a mismatch of bases, not an
underspend. `audit.plan_variance_reconciliation` (`sql/audit/800`, evidence `evidence/full/plan_variance_reconciliation.csv`) takes
every year x Spending Review group x plan measure from FY2022-23 (364 cells: resource DEL excluding depreciation, capital DEL,
departmental resource AME and capital AME), sets the model's outturn on the plan's basis beside the plan, and measures both against an
independent outturn: the annual restated file to 2024-25, the PSS for DEL in 2025-26. The two files that make the comparison possible:
the annual basis table now holds AME (`sql/dw/575`, **tested** by `sql/tests/801`), and `audit.pesa_2026_basis_change` records that PESA
2026 is on another framework.

**Headline variance, before and after** (GBP bn, all groups; the model, **tested** by DAX test 801 and `sql/tests/802`):

| Year | Before: all four measures | After: DEL only (resource excluding depreciation + capital) | AME (left out of the headline) |
|---|---|---|---|
| 2022-23 | -148.76 (-13.4%) | -23.54 (-4.2%) | -125.22 |
| 2023-24 | -114.76 (-9.9%) | -7.34 (-1.3%) | -107.42 |
| 2024-25 | -123.75 (-9.9%) | -7.65 (-1.3%) | -116.09 |
| 2025-26 | -110.24 (-8.5%) | -8.50 (-1.3%) | -101.74 |

**Verdicts**: 364 cells: 233 `ok`, 4 `fixed`, 120 `explained`, 7 `unexplained` (**tested**: `sql/tests/802` pins the seven). `ok` is a variance within
tolerance (the larger of 5% of plan and 100m), or a DEL variance above it that the independent outturn confirms (the model and the
independent outturn differ by less than the larger of 2% of plan, 10% of the variance and 100m): a real over- or underspend, such as
Defence capital DEL, 8% under plan in 2025-26 and the PSS agrees to 0.3%. By year: 2022-23 50 ok, 4 fixed, 26 explained, 3 unexplained; 2023-24
55, 0, 34, 2; 2024-25 67, 0, 27, 2; 2025-26 61, 0, 33, 0.

**What was wrong (fixed), with its test**

1. FY2022-23: the plan exists only for BEIS, DCMS and DIT as one group, and the outturn was on the current structure (Energy Security,
   Science, Business and Trade, Culture), so the combined group had a plan of 19.69bn resource and 20.55bn capital and no outturn (-100%), and four
   other groups had outturn and no plan. `dw.plan_group_rule` (`sql/dw/552`) puts the outturn of the departments 013, 048 and 084 as the release reported
   them in the combined group, in `dw.outturn_plan_basis_inyear` and in the model's outturn view. The phasing profile still reads the current-structure
   group (`dw.outturn_plan_line.sr_group_key`), so no phased plan moves. Test `sql/tests/800` (its last clause returns four rows on the old logic, which I ran) and the
   updated `sql/tests/556`. The variance that remains for the group is a real one: resource -2.25bn (-11.4%), capital -3.01bn, and AME,
   explained below. No real total moves (`evidence/expected/real_fact_totals.csv` is unchanged; this regroups).
2. Departmental AME was not on the annual basis table, so an AME variance could not be set against a final outturn: `sql/tests/801` returns the missing
   rows on the old logic.
3. The headline mixed DEL, a limit Parliament votes, with departmental AME, a forecast. This is a presentation fix, not a number change: a report filter keeps
   resource DEL excluding depreciation and capital DEL on the Executive, Variance and Group detail pages (`tools/build_report.sh report_filters`), and the P&L page lost its plan columns.

**What is genuine and why (explained)**

| Cause | Size | Source and test |
|---|---|---|
| Departmental AME is a forecast, and the in-year files are a first look. The AME plan is a PESA forecast; the in-year outturn lacks the year-end provisions, impairments and pension entries that the annual file carries. In 2024-25 resource AME is 471.2bn in-year, 495.8bn in the annual file and 494.6bn in PESA December 2025; the largest category gaps are take-up of provisions (-17.6bn) and impairment/revaluation (-14.0bn) | AME variance 101.7bn to 125.2bn a year, of which first look to final -22.8bn in 2024-25 and +38.3bn in 2022-23 | `audit.plan_variance_reconciliation` (`gap_first_look`, `first_look_cause`); `docs/profiling/oscar-annual-bud.md` ("AME moves after June") |
| PESA 2026 puts about 20bn (2022-23), 40bn (2023-24) and 45bn (2024-25) of outturn in resource AME that PESA December 2025 has in resource DEL (the ringfenced depreciation), so its AME outturn is not on the framework of the plans. 2025-26 AME has no outturn on the plan's framework | RDEL -19.9, -40.1, -46.9bn; RAME +20.0, +40.3, +44.6bn | `audit.pesa_2026_basis_change`, `sql/tests/803` |
| Single Intelligence Account: a plan, no outturn in OSCAR | DEL plan 3.83, 4.20, 4.51, 5.03bn a year (all of the plan-only gap) | `authored/sr_group.csv` (member type plan only), `sql/tests/802` |
| Home Office: fee income that the in-year files lack. Category T302 (receipt of fees and charges) is -1.11bn in-year and -6.18bn in the annual file in 2024-25, with nothing else in the group more than 0.15bn apart; in 2022-23 the same income sits under B102 sales. The PSS agrees with the annual file. I do not know why the in-year files lack it. 2025-26 has no annual file: the gap (5.30bn) is carried from 2024-25 and labelled so | +3.53, +4.04, +4.62, +5.30bn a year | `evidence/full/plan_variance_reconciliation.csv` |
| Scotland 2022-23: the in-year outturn is net of the block grant adjustment; the plan and the annual file are gross | -10.90bn against PESA 2026's memo line of -11.15bn (2023-24: -11.00bn against -11.26bn, where the plan is net as well, so that cell is ok) | PESA 2026 Table 1.3 memo line, `sql/tests/511` for the plan flag |
| DEL first look against the annual file overall | DEL first-look gap -1.73, +0.38, +5.90 and +6.69bn a year, almost all Home Office | the table above |

This also settles an earlier note: the "about 5.5bn of other non-cash items" that the in-year resource DEL basis was said to carry from 2024-25 is not non-cash. The
ringfenced categories (P101, P201, P301, Z201) all sit in the PESA group DEPRECIATION, so dropping that group is the ringfence basis; the 5.5bn is the Home Office fee income.
The bridge, the plan grain, the 2023 split, Supplementary against Main Estimates and the units and signs (suspects 3 to 7) produced no cell that the audit could not
account for: sums tie to the published totals (`sql/tests/509`) and to the independent outturn within the tolerances above.

**Residual: seven unexplained cells**, all small (variance under 1bn, 0.1bn to 0.66bn against the annual file), none a headline item. For each I tried the largest
economic category (under 60% of the gap), the PSS group-boundary carry-forward (which needs a prior year that agreed with the annual file) and the sibling groups: CLG Communities resource DEL 2022-23
(-0.35bn, -8.1%; the MHCLG group splits into two Spending Review groups and the annual file and the bridge disagree on the split), Environment, Food and Rural Affairs
resource AME 2022-23 (-0.86bn) and 2024-25 (-0.37bn), Justice resource AME 2022-23 (-0.33bn), Business and Trade capital DEL 2023-24 (-0.20bn, -14.2%) and resource
AME 2024-25 (-0.70bn), Foreign, Commonwealth and Development Office resource AME 2023-24 (+0.43bn).

**Not done**: the 2025-26 AME cells and the Home Office 2025-26 cell are explained by a carry-forward, not measured: no annual file for 2025-26 exists in `data/`.

## Known residuals (published, not hidden)

| Residual | Size | What I know | Where it is |
|---|---|---|---|
| PSS capital DEL against the annual outturn, excluding Scotland | -0.46% in 2023-24 and -0.36% in 2024-25, against a tolerance of 0.1% | the cause is unknown. Resource DEL excluding depreciation passes in the same years. Test 412 pins these two as the only failures, so a third one fails the build | `evidence/full/pss_vs_outturn.csv`, `sql/tests/412` |
| BUD against the in-year releases, DEL | within 3.5% for all 15 pairs (-3.18% to +3.40%) | the in-year June snapshot is not final outturn, and the annual files are restated. The 2023-24 pairs sit close to the tolerance | `evidence/full/bud_vs_inyear_del.csv`, `sql/tests/408` |
| Current-structure hold-out, DSIT, all budgets | -8.66bn (-45.2%) in 2021-22 and -10.53bn (-44.5%) in 2023-24 | I have no tested explanation. At DEL level DSIT is within 2.1% in those years, so the gap is in the layers the annual file carries and the in-year file does not, but I did not trace it | `evidence/full/current_structure_holdout.csv`, `docs/data-dictionary/current-structure.md` |
| FY2023-24 plan-basis gaps | Scotland resource DEL excluding depreciation: annual outturn is 11.0bn above the plan, and the in-year figure equals the plan to the pound. CLG Local Government: in-year +5.0bn against annual. Home Office: in-year +3.8bn against annual (+20%) | Scotland and Home Office are now explained, see section 9: Scotland is the block grant adjustment (the in-year files and the 2023-24 plan are net of it, the annual file is gross), Home Office is fee income that the in-year files lack. CLG Local Government is still not traced (it is in the 2022-23 cell list of section 9 as category D501 current grants to local government) | `evidence/full/plan_basis_inyear_vs_annual.csv`, `evidence/full/plan_variance_reconciliation.csv` |
| NHS Pension Scheme unit errors | two lines (the error and its offsetting line), three findings each, thirteen flagged fact rows | amounts 1,000 times too large in one release and corrected in the next; the restatement view can exclude or annotate them | `dw.dq_issue`, `sql/tests/309` |
| Annual files as a control | DEL at total level only | not usable for AME, non-budget or the grand total, and not as a hard department-level check before 2024-25 | `docs/data-dictionary/annual-restated.md` |

### Forward notes: two known bad forecast returns

The forecast backtest (departments' own monthly returns, FY2017-18 to FY2022-23) is not built yet. Two returns are
known to be wrong at source and will be reported, with the accuracy results shown with and without them:
FY2020-21 R0, where the Foreign, Commonwealth and Development Office keyed amounts in pounds (about 1,000 times
too large), and FY2018-19 R1, which has no Department of Health rows (`docs/profiling/oscar-annual-extracts.md`).
This is **designed**: no table in the database holds a return yet.

## Judgements I made that the data cannot settle

Three decisions I made where the sources do not say what is right. Each is stated with its evidence and my
confidence, so that a reader can disagree. Figures are from the full-scope build.

**1. The 37 OSCAR Plans rows with `USAGE_CODE = OUTTURN` are kept.** Confidence: medium.

- Evidence: `raw.plan_oscar` has 37 rows whose version is PLANS and whose usage is OUTTURN: 4 in FY2017-18, 4 in
  FY2018-19, 5 in FY2019-20, 14 in FY2020-21 and 10 in FY2021-22, together GBP 30,880,243 thousand, which is 0.22%
  of the GBP 13,746,621,755 thousand of all plan rows in the five extracts. They are DHSC pension, housing revenue
  account and London Underground lines and a few small bodies.
- Why I keep them: the publisher's own row counts for the PLANS version (`data/audit/extract_file_control_totals.csv`)
  include them, so dropping them would break the control that ties the load to the published file. The usage flag
  says how the line is used (outturn comparison), not that it is not a plan line.
- What I could be wrong about: they may be outturn lines filed under the plan version by mistake. If so, grain A
  plan totals are 0.22% too high in those years. The count is pinned by `sql/tests/521`, so a change in source
  is noticed.

**2. Exiting the European Union maps to the Cabinet Office.** Confidence: medium.

- Evidence: 187 plan rows in the extracts, all of organisation DEU077, FY2017-18 to FY2020-21 (47, 54, 66 and 20
  rows; GBP 160,797, 186,859, 84,076 and 0 thousand, GBP 431,732 thousand in all). The department closed in
  January 2020; its functions went to the Cabinet Office, which no file in the project states.
- What the choice changes: only the Spending Review group of those grain A rows (`authored/plan_name_map.csv`, one row,
  `confidence = medium`). At organisation grain the plan stays with DEU077. The current-structure map treats the
  department's outturn lines separately, as an Unallocated member, so the plan and the outturn of this
  department are not compared at group level.
- The alternative is a non-department member, which would keep the plan out of every department group; I judged
  that the Cabinet Office is the more likely owner.

**3. FY2022-23 plans are compared at a combined pre-2023 group.** Confidence: high that it cannot be split, medium
that the comparison is clean.

- Evidence: the FY2022-23 Estimates and PESA tables are on the department structure of before February 2023, so
  BEIS, DCMS and DIT are published as they were. In the fact the group `Combined pre-2023: BEIS, DCMS and DIT`
  holds, for 2022-23, resource DEL excluding depreciation 19,692,000 and capital DEL 20,550,000 (grain C), and
  administration and AME (grain D), in GBP thousand. No source publishes the split onto the new departments.
- What I did: the plan is kept at the combined group; its outturn comes from the departments 013, 048 and 084
  as the release reported them (`pre2023_as_reported` rows of `authored/department_sr_group.csv`), tested by
  `sql/tests/554`. The other groups map one to one only where the group did not change; for them the as-reported view
  and the current structure agree.
- What I could be wrong about: bodies that moved between those three departments inside the combined group are
  invisible, which is the point of combining them; a body that moved to a department outside the three is not
  followed. I did not quantify that.

The same three are recorded with their evidence in [data-dictionary/plans.md](data-dictionary/plans.md).

## Timings

CI, job `pipeline-sql`, whole job: 8 min 30 s on a cold cache and 4 min 32 s with the uv cache restored (runs
44256921066 and 44258121672; the per-step seconds are in [pipeline.md](pipeline.md#continuous-integration)). The
runner's speed varied by about a factor of two between the two runs. Local builds: committed scope 3 min 13 s, full
scope 9 min 33 s, on a quiet machine (see above). The full build is not run in CI.

## Appendix: every assertion

The list below is generated from the files by `uv run --project pipeline ukfr inventory --write` and checked by
`pipeline/tests/test_inventory.py`, so it cannot drift: the test fails if a SQL test lacks its `-- test:`
header, or if a test was added, removed or re-scoped without regenerating this block. The scope is `full` for a
test that needs `-- requires:` objects or `-- marker: localdata`, otherwise `committed`. The evidence file is the
file under `evidence/` that the test reads, found from the `audit.` tables named in its text; "none" means it
queries the warehouse directly.

<!-- inventory:begin (generated by `ukfr inventory --write`; do not edit by hand) -->

138 SQL assertions (100 committed scope, 38 full scope) and 49 Python assertions that read the built database (37 committed scope, 12 full scope).

### SQL assertions (`sql/tests/`)

| Id | What it proves | Scope | Marker | Where it runs | Evidence file |
|---|---|---|---|---|---|
| `001` | every quarterly release from 2019-03 to 2026-09 (31 of them) has exactly one loaded primary file | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `002` | raw rows equal the data rows of the file for all primary files (loaded + quarantined = read = expected) | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `003` | the exact raw amount sum equals amount_sum of the control table for all primary files | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `004` | the staged DECIMAL(19,4) sum equals amount_sum_rounded_4dp for every release | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `005` | staged rows equal data rows minus exact-zero rows, and the raw zero-row count equals the control table | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `006` | stg.inyear_snapshot is unique on (release, organisation, sub-segment, economic category, control budget detail, period) | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `007` | each release covers exactly its expected year to date, in its own financial year | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `008` | a file that is not the primary of its release is proven identical to the primary and has no rows loaded | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `009` | no row of the real releases is in quarantine | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `010` | the sha256 of every data file, hashed again at load time, equals the manifest and the control table | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `011` | the 71 "Period 0 - 18-19" rows exist in release 2019-06 and nowhere else, and stay in the staged table as period 0 | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `012` | fiscal_quarter is derived from the month: (period + 2) / 3 for periods 1-12, NULL for period 0 | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `013` | stg.release has one row per release, sequence 1..31 in publication order, one version label, a financial year and a highest period that match the rule | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `014` | no FLOAT or REAL column exists anywhere, and the staged amount is DECIMAL(19,4) | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `015` | every staged row traces to a raw row, keeps its amount rounded to four places, and was not exactly zero | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `016` | audit.file_control has a row for every data file and none of them fails a measure | committed | - | CI (pipeline-sql) and local builds | evidence/build/file_control.csv |
| `200` | every table in schema authored says in its description that it is authored data | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `201` | in raw data a release publishes one organisation name and one department label per organisation code | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `202` | no department number carries two department labels in one release | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `203` | department periods run forwards, do not overlap within a number, and have a known member type | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `204` | every department number reported in a release has exactly one authored naming period covering that release | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `205` | every department label a release publishes is listed in published_labels of the authored period that covers it | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `206` | every label listed in published_labels is published at least once inside its period (no stale evidence) | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `207` | every department_key used by the organisation dimension or the release map exists in dim_department, and only Unknown has key -1 | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `210` | each override has a key, runs forwards, uses a known reason, and no two overrides cover one code in one release | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `211` | every override row is used by at least one organisation code in one release | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `212` | a code that merges into another is reported together with it in the same release and shares its durable key | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `220` | the versions of a durable key start at its first release, run forwards, and each starts the release after the previous one ends | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `221` | each durable key has at most one current version and exactly one latest version, and the current one is the latest | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `222` | a version is current exactly when it is the key's latest version and the key is reported in the latest release | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `223` | in one release a durable key is carried by one organisation code only, apart from a merged coding error | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `224` | a version after the first has a tracked change flag, and a flagged row always starts a version | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `225` | a name change to a name seen before, or away from a name that comes back, is an alias and starts no version | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `226` | every version has spellings in the alias table, and their release counts add up to the version's reported releases | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `230` | every (organisation code, release) in stg.inyear_snapshot has exactly one row in the release map, and the map has no other rows | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `231` | every row of stg.inyear_snapshot joins to the release map, and none lands on the Unknown member | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `232` | the version a release maps to belongs to the durable key, covers that release, and has the code itself unless it is a merged code | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `233` | the department_key in the release map is the department number of the code, in the naming period covering the release | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `240` | stg.current_structure_map has exactly one row for every (organisation_key, sub_segment_code) pair in the snapshot, and no other | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `241` | the current structure map keeps its contract: an allowed method, an estimate only on an authored line, and a line that follows its organisation stays in the department number of the durable key's latest version | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `300` | for every release R, the deltas up to R for R's financial year equal R's snapshot on every line, and are zero for every line R does not report | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `301` | for every release R, the deltas up to R for R's financial year equal R's snapshot for every department as reported | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `302` | for every release the deltas up to it for its financial year add up to amount_sum_rounded_4dp of the release's primary file in the control table | committed | - | CI (pipeline-sql) and local builds | evidence/build/delta_invariant.csv |
| `303` | every delta row of a release is in the release's own financial year | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `304` | every key in the fact is not NULL and exists in its dimension, none resolves to Unknown, a dq_issue_id exists in dw.dq_issue, and no zero amount is stored | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `305` | the organisation, department, segment, account and control budget dimensions each have exactly one Unknown member with key -1 | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `306` | revision_no 0 rows are exactly the lines ever reported, each with its first reported value; revision numbers run 0, 1, 2 ... in release order | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `307` | dim_period has 13 rows for each of the 11 financial years from 2018-19 to 2028-29; period 0 appears in the fact only for 2018-19 and does appear there | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `308` | every economic category has exactly one economic budget and one income / expenditure value, the budget is the one the latest release gives, and no category is left unclassified | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `309` | rule a flags the NHS Pension Scheme lines (sub-segment X903A002 as a unit error, X903A003 as its offsetting line, three findings each) in the release pairs 2023-09 to 2023-12 and 2025-12 to 2026-03 and nothing else; the fact rows carrying a dq_issue_id are exactly, for each finding, the delta rows of the line-month from the one that set the amount (the delta row of largest absolute size at or before the first release of the pair) to the one that corrected it | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `310` | rule b is September 2022 only and covers every row of the release, rule c is the Period 0 rows of June 2019 only and matches raw, rule d is the one authored coding error | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `311` | a line carries one department in all its releases, and current_department_key is what stg.current_structure_map gives for the organisation version and sub-segment | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `312` | dim_release matches stg.release, dim_scenario has the five scenarios, every sub-segment has one name per release, dim_control_budget has one control budget per detail code, the fact amount is DECIMAL(19,4), and the authored account table holds no amounts | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `313` | the independent recount agrees with the profiled delta row count for every release, and the differences between the fact and the profile are fully explained (rounding, key changes within a year, letter case of a code) | committed | - | CI (pipeline-sql) and local builds | evidence/build/delta_rowcount.csv |
| `400` | raw.oscar_bud rows and exact sums equal data/audit/bud_file_control_totals.csv for each of the 15 workbooks | full | localdata | local full build only | data/audit/bud_file_control_totals.csv |
| `401` | the loaded BUD data agrees with the independent recomputation (data/audit/bud_independent_control.csv) | full | localdata | local full build only | data/audit/bud_independent_control.csv |
| `402` | 15 BUD workbooks are loaded with matching hashes, every raw row has a loaded file, and the guidance files are recorded as skipped | full | localdata | local full build only | none (query on the warehouse) |
| `403` | no BUD or PSS row is quarantined | full | localdata | local full build only | none (query on the warehouse) |
| `404` | dw.fact_outturn_annual sums to amount_sum_excluding_closed for each workbook, and holds every non-Closed row | full | localdata | local full build only | none (query on the warehouse) |
| `405` | dw.fact_outturn_annual has one row per grain, the control budget follows the detail, and the flags follow their rules | full | localdata | local full build only | none (query on the warehouse) |
| `406` | within one workbook an organisation has one SR group and one department group, so (vintage, year, organisation) is the key of stg.bud_sr_group_by_organisation | full | localdata | local full build only | none (query on the warehouse) |
| `407` | CLG085.GROUP maps to two Spending Review groups, so the organisation and not the department group keys the SR group | full | localdata | local full build only | none (query on the warehouse) |
| `408` | every one of the 15 year and vintage DEL pairs is within 3.5%, and AME, non-budget and total are boundary differences, never failures | full | localdata | local full build only | evidence/full/bud_vs_inyear_del.csv |
| `409` | the six in-year organisation codes missing from the BUD are reported with their in-year amounts, and kept in stg.inyear_snapshot | full | localdata | local full build only | evidence/full/bud_inyear_org_match.csv |
| `410` | raw.pss rows and amount sums equal data/audit/pss_file_control_totals.csv and the independent recomputation, for every year | full | localdata | local full build only | data/audit/pss_file_control_totals.csv |
| `411` | every PSS Spending Review group name is matched to an OSCAR group (exactly, or through the three authored aliases) and the aliases hold no amounts | full | localdata | local full build only | none (query on the warehouse) |
| `412` | PSS against BUD passes its tolerance for resource DEL excluding depreciation in every year; the only failures are capital DEL in 2023-24 and 2024-25; PSS totals tie to the PSS rows | full | localdata | local full build only | evidence/full/pss_vs_outturn.csv |
| `450` | every (organisation_key, sub_segment_code) in the snapshot maps to exactly one department that exists now or to an Unallocated member that exists, never to Unknown, a closed department or a missing key | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `451` | an Unallocated member is used only for the former department it is named after, exists with member_type Unallocated, and no Unallocated line is estimated or authored | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `452` | for every release the fact's as-at total by current department equals its total by reported department and the snapshot total, and by current department it equals the snapshot recomputed through the map | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `453` | every authored current-structure row is unique, names a durable key that exists, decides at least one line (no dead row), puts those lines in the department it names, and an estimated row is flagged on the lines it decides | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `454` | all 204 sub-segments that the June 2023 release reports under the BEIS department map to DSIT, DESNZ, DBT or the BEIS Unallocated member, never to a department that no longer exists | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `455` | the hold-out table adds up to the totals of audit.bud_vs_inyear_del for the 2025-11 vintage (DEL and total), covers every year the vintage holds, and every BUD department group has a mapping row | full | localdata | local full build only | evidence/full/bud_vs_inyear_del.csv, evidence/full/current_structure_holdout.csv |
| `500` | all 9 Estimates workbooks and 7 PESA and SR25 workbooks were read, their hashes equal the manifest, and the rows counted per file equal the rows in the raw tables | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `501` | every Estimates sheet-year and every PESA department-group section loaded equals the sheet's own published total row, within the rounding of the published figures | committed | - | CI (pipeline-sql) and local builds | evidence/build/plan_sheet_control.csv |
| `505` | every plan line maps to a Spending Review group or is explicitly plan-only, non-department or combined pre-2023; nothing is unmapped, and every map target is a member of dw.dim_sr_group of the same type | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `506` | dw.dim_sr_group holds the 23 Spending Review groups with the names of the latest BUD, the Single Intelligence Account as plan-only, one combined pre-2023 member, the non-department members and one outturn-only member with outturn and no plan row | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `507` | no plan row carries a FLOAT or an unconverted unit: every cell with a value has a recognised unit and a converted amount, the multiplier is the one the unit text implies, and fact amounts are DECIMAL(19,4) | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `508` | dw.fact_plan has one row per plan source, year, group, organisation, control budget detail, economic budget and measure; the grain code agrees with the plan source and the years; organisation is set only at grain A and each organisation sits in one group per year | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `509` | for every Estimates and PESA year and measure in dw.fact_plan, the sum of the fact rows (reserves, the Single Intelligence Account and other non-department lines included) equals the sheet's own published total, converted to GBP thousands, within the rounding of the published figures | committed | - | CI (pipeline-sql) and local builds | evidence/build/plan_sheet_control.csv |
| `510` | dw.plan_coverage and audit.plan_coverage describe dw.fact_plan exactly: same rows, source lines and totals per plan source, year, measure and grain | committed | - | CI (pipeline-sql) and local builds | evidence/build/plan_coverage.csv |
| `511` | the Scotland block grant adjustment flag of each Estimates workbook agrees with the figures: a gross_of_bga line is within 10 percent of a PESA Scotland figure for the same year on the excluding-depreciation basis; a net_of_bga line is at least 15 percent below those figures, or (2026-27, no PESA gross figure) carries the adjustment as a memo line | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `512` | nothing authored can reach a real total: the authored plan tables hold no amount columns, the plan dimensions hold no amounts, and the fact total of the Estimates grains equals the total of the published figures they come from (grain A is checked in 521) | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `520` | OSCAR Plans have 8,902 rows at the load grain for FY2019-20 to FY2021-22, the rows read per extract equal the extract's own plan row count, and the totals tie to plan_oscar_totals.csv per year, department group, control budget detail and economic budget (amounts and source row counts) | full | localdata | local full build only | none (query on the warehouse) |
| `521` | every OSCAR plan key has one department group and one Spending Review group, every plan row has an amount that parses, all rows are PLANS rows with a recognised control budget, and the grain A rows of dw.fact_plan carry the whole OSCAR total | full | localdata | local full build only | none (query on the warehouse) |
| `522` | every SR group name in the OSCAR plan rows has an entry in the plan name map | full | localdata | local full build only | none (query on the warehouse) |
| `537` | the 2026-27 Main Estimate (a table not titled excluding depreciation) is on the excluding-depreciation basis: each department line equals PESA 2026 Table 1.3 resource DEL for 2026-27 to the nearest GBP million, and the Estimates total equals the PESA total once reserves, the OBR allowance and the Budget Exchange adjustment are taken out | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `550` | every organisation version and sub-segment pair of the outturn has exactly one Spending Review group in dw.outturn_sr_group_bridge, none through an unknown department, none in a plan-side member (in particular not Unallocated central funds), and the regrouped lines add up to the fact | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `551` | the bridge group of a pair is what authored/department_sr_group.csv says for the current department number (or the organisation exception), every current row of the file is used, and CLG Communities and CLG Local Government are split by organisation | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `552` | every phasing profile has the periods 1 to 12 once, its shares add up to exactly 1, flat profiles are twelve twelfths (the last one takes the rounding remainder), and every row is flagged derived | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `553` | the profile method is recomputed from dw.fact_outturn without the profile code: prior_year_outturn wherever the year-end release of the prior year has a positive total for the profile's lines, flat_prior_not_positive where it has lines with a total of zero or less, flat_no_prior_year otherwise | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `554` | the method of the organisation profiles (plan grain A) and of the combined pre-2023 group profiles is recomputed from dw.fact_outturn at the year-end release of the prior year, without the profile code | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `555` | every dw.fact_plan row that has a calendar is spread over periods 1 to 12 exactly once, the twelve amounts add up to the plan amount with no difference at all, every phased row is derived and the Plan (phased) scenario, and the plan fact itself carries no phased amount | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `556` | for every release and every plan measure the in-year plan-basis outturn equals the matching selection of dw.fact_outturn (sum of the deltas of the release's financial year up to and including the release), in total and for each Spending Review group (the group the plan is published under: the bridge, except FY2022-23 outturn of BEIS, DCMS and DIT as reported, which is the combined group); the year-end rows are flagged, and the excluding-depreciation measures carry the basis note | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `558` | the phased plan and the phasing profile are flagged derived, labelled DERIVED, and nothing outside this feature reads or points at the phased plan, except the model's derived-labelled view of it, which sql/tests/706 pins (the row counts and sums of the real facts are pinned in evidence/expected/real_fact_totals.csv and checked by pipeline/tests/test_real_totals.py) | committed | - | CI (pipeline-sql) and local builds | evidence/expected/real_fact_totals.csv |
| `559` | none of the tables of this feature has a float or real column, and every amount is decimal(19,4) and every share decimal(19,10) | committed | - | CI (pipeline-sql) and local builds | evidence/full/plan_basis_inyear_vs_annual.csv, evidence/build/plan_phasing_summary.csv, evidence/build/sr_group_bridge_summary.csv, evidence/full/sr_group_bridge_vs_bud.csv |
| `561` | the organisations on which the bridge and the newest annual release (BUD) disagree about the Spending Review group are exactly the 31 (organisation, bridge group) pairs listed here and read in docs/data-dictionary/plan-phasing.md; every other organisation present in both agrees; only BIS084 (the BEIS core department, whose lines the current structure splits between four groups) has more than one row | full | localdata | local full build only | evidence/full/sr_group_bridge_vs_bud.csv |
| `650` | the load holds exactly the 83 returns (R0 to R13 for FY2017-18 to FY2020-21 and FY2022-23, R1 to R13 for FY2021-22), each from the family the design names, each file hash equals the manifest, and the source rows of every return equal the records behind its cells | full | localdata | local full build only | none (query on the warehouse) |
| `651` | at return x organisation x economic category x control budget detail x economic budget x month (periods 1 to 12) the load holds exactly 1,419,936 rows for the annual extracts and 703,146 for the MFO files, the counts the profiling gave | full | localdata | local full build only | none (query on the warehouse) |
| `652` | no organisation is both DRAFT and CONFIRMED in one return, every status is one the files use (CONFIRMED and DRAFT in the extracts, Confirmed and Locked in the MFO files), and every control budget name and economic budget is recognised | full | localdata | local full build only | none (query on the warehouse) |
| `653` | dw.forecast_return is unique at return x organisation x economic category x control budget detail x economic budget x period, the cells behind each row agree on one department group and one Spending Review group, and the rows plus the quarantined grain keys equal the grain keys of the staged cells | full | localdata | local full build only | none (query on the warehouse) |
| `654` | every row of dw.forecast_return carries the organisation version and durable key of dw.dim_organisation and a known department (never Unknown), and the staged cells split exactly into dw rows and quarantined cells: same cell count, and the exact amount of every return equals dw plus quarantine within the four-decimal rounding of the rows | full | localdata | local full build only | none (query on the warehouse) |
| `655` | period 0 (budget adjustments) is kept and flagged, exists only in R13 of the annual extracts, is never in a return's total (dw.forecast_return_header), and never reaches the own-forecast inputs, the profile, the month comparison or the accuracy | full | localdata | local full build only | none (query on the warehouse) |
| `656` | the status of every row follows the rule from its return number n and month m: actual when m < n, provisional when m = n (n from 1 to 12), forecast when m > n, adjustment at period 0; is_actual is m <= n for months 1 to 12; R0 is all forecast and R13 all actual; every return has all twelve months | full | requires dw.forecast_return | local full build only | none (query on the warehouse) |
| `657` | for every return (R13 included), every month and period 0, the loaded rows and the exact amount equal a recomputation from the source files by code that shares nothing with the reader (data/audit/forecast_independent_control.csv): difference 0 in rows and in amount; and dw.forecast_return agrees with it within the four-decimal rounding of its rows | full | localdata | local full build only | data/audit/forecast_independent_control.csv |
| `659` | audit.forecast_r13_vs_outturn covers FY2018-19 to FY2022-23 against both the annual vintages that hold the year and the year-end in-year release, its R13 total equals the independent recomputation of R13 months 1 to 12, and every gap is the difference of its two amounts (a comparison, not a gate: the size of the gaps is explained in the data dictionary) | full | localdata | local full build only | evidence/full/forecast_r13_vs_outturn.csv |
| `660` | no leakage. Every own-forecast row at point n carries lineage that says its inputs come from return n and from months up to n; the input table equals, both ways, the rows of dw.forecast_return with return = n and month <= n; the prior-year profile equals the R13 of the prior year; and both methods recomputed from that restricted set alone (same arithmetic and the seasonal guard, read straight from dw.forecast_return) equal dw.forecast_own exactly | full | requires dw.forecast_own, dw.forecast_own_input, dw.forecast_prior_profile, dw.forecast_return, dw.forecast_return_header | local full build only | none (query on the warehouse) |
| `661` | the own forecast exists only for returns R1 to R11 (R0 has no actual month, R12 has no month left), forecasts exactly the months n + 1 to 12, has a seasonal method only where the prior year's R13 exists (never in FY2017-18) and names that year, every run-rate row equals the year to date divided by n, and the seasonal forecast exists exactly where the guard holds: the prior year's months 1 to n have the same sign as the year to date and are at least a tenth of the prior year's full total | full | requires dw.forecast_own, dw.forecast_return_header | local full build only | none (query on the warehouse) |
| `662` | the accuracy table recomputed by a second route, straight from dw.forecast_return (the department's forecast and my run rate, for every department group, budget measure, year and return), gives exactly the same full-year forecast and outturn, forecast-month error, absolute error and absolute outturn, and so the same WAPE and bias; every ratio, full-year and forecast-month, is the ratio of its sums, and MAPE exists only for a full-year outturn of at least GBP 100m | full | requires dw.forecast_accuracy, dw.forecast_return, dw.forecast_return_header | local full build only | none (query on the warehouse) |
| `663` | dw.forecast_return_quality is exactly what its rules give on dw.forecast_return (recomputed here), never flags R13, catches the two known bad returns (FCDO R0 of FY2020-21 keyed in pounds, the Department of Health missing from R1 of FY2018-19), and every flagged department group is marked in dw.forecast_accuracy | full | requires dw.forecast_return_quality, dw.forecast_return, dw.forecast_accuracy, dw.forecast_return_header | local full build only | none (query on the warehouse) |
| `664` | audit.forecast_return_summary has one row per year, its R13 control differences are zero in rows and in amount for every year (and zero in amount for every return), its counts equal the header and the quality table, and audit.forecast_accuracy_headline has both versions for every year and method that has accuracy rows | full | localdata | local full build only | evidence/full/forecast_accuracy_headline.csv, evidence/full/forecast_return_summary.csv |
| `700` | every model view returns the rows of its base table, except the three documented subsets (department: the live members; fiscal year: one row per year of the calendar and of the plan; data quality: plus the "No issue flagged" member) | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `701` | the three model fact views carry the same total as their base fact, every outturn line keeps one Spending Review group and one data-quality key, and every plan row has the Plan scenario | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `702` | the current-structure department view holds every department the outturn fact points at, only live members, each department number at most once, and the Unknown member is not in it | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `703` | the data-quality view is dw.dq_issue row for row plus one member with key 0 that holds no amount and flags no fact row, and key 0 is not an issue id | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `706` | of every view and procedure, only dw.v_model_fact_plan_phased reads the phased plan, nothing reads the phasing profile, and the phased view carries the derived flag and the method on every row | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `720` | the four sign cases of the scenario comparison are real cells of OSCAR Plans against outturn, and each has the sign that the case names | full | localdata | local full build only | none (query on the warehouse) |
| `740` | every account (economic category, and the Unknown member) maps to exactly one detail line of the statement, the line is the one the most specific matching rule names (resolved here a second way, with LIKE on the rule lists), and no two rules of the top specificity disagree | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `741` | the total line of the statement equals the sum of dw.fact_outturn in every financial year, and the sum of the detail lines equals it too, so no amount is lost or counted twice | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `742` | for every subtotal and total line and every year, the line equals the sum of the members its definition lists, taken one level down (a member that is itself a subtotal counts as a whole), and a member list never reaches a detail line by two paths | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `743` | a line with plan scope RESOURCE or CAPITAL adds up exactly the accounts whose economic budget is that budget, and the line with scope ALL adds up every account, so the plan that the source publishes at that level is compared with the same accounts | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `744` | every line has a distinct label (spacers differ by zero-width characters only), an income-positive line holds income accounts only, and the presented amount is the reported amount times the sign factor | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `745` | the statement objects are labelled authored and hold no amount column of any type, and the Unknown account is mapped once | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `746` | the plan on the total line of the statement for 2024-25 is the sum of the four published budgets (resource DEL excluding depreciation 487,520,000, capital DEL 114,587,000, departmental AME resource 551,762,000 and capital 102,672,000, GBP thousands: the totals that sql/tests/509 ties dw.fact_plan to), and administration rows are not added on top | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `760` | every department number an outturn line was reported under maps to exactly one live department of the current structure, so the as-reported structure added over the departments adds back to the total; the numbers that no live Department carries are the four closed ones and nothing else; the view lists each number once | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `761` | the model's outturn view carries the estimated flag of the line's row in the current-structure map for every row, the three estimated lines are the ones the authored file marks, and no other row is flagged | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `762` | the offsetting line of the NHS Pension Scheme unit error is flagged with it. For every unit error on line X903A002 there is an 'offsetting line' finding on line X903A003 in the same release pair, organisation, period, economic category and control budget whose change is the opposite of the first line's change within one per cent; the fact rows flagged for the two lines carry the same release, period and opposite signs within one per cent of each other; and there are thirteen flagged fact rows, six on the unit-error line and seven on its offsetting line (the offsetting line also has a small revision in December 2025 between the row that set the amount and the row that corrected it). Before the rule flagged the offsetting line, this test pinned the opposite (six flagged rows and an unflagged mirror for each). | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `780` | the file-control view has one row for each of the 31 primary release files and the file totals of the audit table, and the plan-coverage view has the rows and totals of dw.plan_coverage; neither adds, drops or changes a number | committed | - | CI (pipeline-sql) and local builds | evidence/build/file_control.csv |
| `781` | the annual-control, PSS-control and load-control views have the rows and the amounts of the audit tables they read (60, 443 and 46 rows in the real data); no row is added, dropped or recalculated | full | localdata | local full build only | evidence/full/bud_file_control.csv, evidence/full/bud_vs_inyear_del.csv, evidence/build/file_control.csv, evidence/full/pss_vs_outturn.csv |
| `800` | the FY2022-23 plan is published for BEIS, DCMS and DIT as one group, so the outturn of the departments 013, 048 and 084 as reported is in that group (in the plan-basis table and in the model's outturn view), nothing else is regrouped, and the group has an outturn wherever it has a plan (with the outturn on the current structure it had a plan and no outturn) | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `801` | dw.outturn_plan_basis_annual holds departmental resource AME and capital AME as well as DEL, and each vintage and year adds up to the control budget detail DEPT AME of the annual file (it had no AME before, so a variance on AME could not be set against the final outturn) | full | localdata | local full build only | none (query on the warehouse) |
| `802` | audit.plan_variance_reconciliation has one row for every year x group x measure the plan or the in-year outturn has from FY2022-23, ties to dw.fact_plan and dw.outturn_plan_basis_inyear in total, each variance equals outturn less plan, the gaps add up to the variance, every row has a verdict, groups without outturn have none, and the unexplained cells are exactly the seven listed here (a change in the list is a change in the finding) | full | localdata | local full build only | evidence/full/plan_variance_reconciliation.csv |
| `803` | PESA 2026 restates the outturn of the same years against PESA December 2025 with resource DEL lower and departmental resource AME higher by nearly the same amount (within 10%), so its AME is not on the framework of the plans of earlier editions | full | localdata | local full build only | evidence/full/pesa_2026_basis_change.csv |
| `804` | the plan variance view the model reads has the rows and the amounts of audit.plan_variance_reconciliation: no row added, dropped or recalculated | full | localdata | local full build only | evidence/full/plan_variance_reconciliation.csv |
| `820` | the user map is synthetic (description, class, reserved domain), every row names a live department of the current structure, no row repeats, the model view keeps every row, and the map holds the three cases the roles are tested with: a user with two or more departments, a user whose department has outturn in fewer years than the data has, and a user who is in no row | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `821` | of every view, procedure and table in the warehouse only dw.v_model_user_department and dw.v_model_user_plan_group read the synthetic table, nothing reads those two views, no foreign key points at the synthetic table, and the synthetic and scale schemas hold exactly the one table, with no numeric column | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `822` | the groups whose plan a user may see are exactly those with at least one department member all of whose department numbers (authored/department_sr_group.csv, basis current or pre2023_as_reported) are among the user's departments, recomputed from the authored text table with a different query; a group with no department member is never visible | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `823` | the invented users see the plan groups docs/security.md lists: Health (NHS) for the two-department NHS user, the Defra, Transport and HM Treasury groups for their single-department users, both CLG groups for the user of department 085, the combined pre-2023 group and its three current groups for the three-department user, and no group for the Cabinet Office user and the Parliamentary Works Grant user | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |

### Python assertions that read the built database (`pipeline/tests/`)

| Test | What it proves | Scope | Marker | Where it runs | Evidence file |
|---|---|---|---|---|---|
| `test_audit_output::test_exact_sum_text` | exact sum text | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_audit_output::test_the_audit_export_is_deterministic_and_matches_the_committed_evidence` | the audit export is deterministic and matches the committed evidence | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_bud_reference_maps::test_department_group_map_reproduces_the_profile` | department group map reproduces the profile | full | localdata | local full build only | none (query on the warehouse) |
| `test_bud_reference_maps::test_organisation_type_map_reproduces_the_profile` | organisation type map reproduces the profile | full | localdata | local full build only | none (query on the warehouse) |
| `test_bud_reference_maps::test_account_hierarchy_reproduces_the_profile` | account hierarchy reproduces the profile | full | localdata | local full build only | none (query on the warehouse) |
| `test_bud_reference_maps::test_sr_group_by_organisation_agrees_with_the_department_group_map` | Every (department group, SR group) pair of an organisation row is a pair of the department group map. | full | localdata | local full build only | none (query on the warehouse) |
| `test_bud_reference_maps::test_pss_against_bud_by_group_reproduces_the_profile` | The profile compared PSS with the November 2025 BUD by SR group, summing every row of the workbook. | full | localdata | local full build only | evidence/full/pss_vs_outturn.csv |
| `test_bud_reference_maps::test_bud_totals_reproduce_the_profile_reconciliation` | `bud_inyear_reconciliation_total.csv`: BUD amounts equal exactly, in-year amounts to the staging | full | localdata | local full build only | evidence/full/bud_vs_inyear_del.csv |
| `test_bud_reference_maps::test_bud_totals_reproduce_the_published_comparison_lines` | `bud_pesa_check.csv` holds the November 2025 BUD sums that the profile compared with PESA. | full | localdata | local full build only | none (query on the warehouse) |
| `test_bud_reference_maps::test_the_organisation_match_reproduces_the_profile` | the organisation match reproduces the profile | full | localdata | local full build only | evidence/full/bud_inyear_org_match.csv |
| `test_bud_reference_maps::test_the_committed_full_scope_evidence_equals_the_build` | `evidence/full/` holds the four audit tables that only a full build writes (the committed-scope | full | localdata | local full build only | none (query on the warehouse) |
| `test_current_structure::test_the_disagreements_are_decided_by_their_authored_rows_in_the_built_map` | the disagreements are decided by their authored rows in the built map | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_current_structure::test_the_204_beis_sub_segments_split_by_rule_as_documented` | The profile found 194 with one successor, 1 with two and 9 with none. By the rules in the map the split is | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_current_structure::test_a_line_of_an_organisation_with_a_home_never_follows_the_code_of_another_department` | The code rule is only for an organisation whose department closed. The audit table lists the lines it would | committed | - | CI (pipeline-sql) and local builds | evidence/build/current_structure_code_rule_rejected.csv |
| `test_current_structure::test_is_current_and_is_live_differ_only_for_the_three_departments_the_partial_september_release_omits` | `dim_department.is_current` is false for the National Audit Office, the Crown Estate Office and the Judicial | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_dim_organisation::test_beis_core_becomes_dsit_core_under_the_same_code_without_merging_history` | beis core becomes dsit core under the same code without merging history | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_dim_organisation::test_dit_core_becomes_dbt_core_under_the_same_code_without_merging_history` | dit core becomes dbt core under the same code without merging history | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_dim_organisation::test_dfid_core_becomes_fcdo_core_when_the_code_is_renamed_and_the_department_label_follows_later` | dfid core becomes fcdo core when the code is renamed and the department label follows later | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_dim_organisation::test_fco_core_merges_into_fcdo_core` | fco core merges into fcdo core | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_dim_organisation::test_ofcom_keeps_one_durable_key_across_its_prefix_change` | ofcom keeps one durable key across its prefix change | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_dim_organisation::test_ukg_prefix_is_split_into_two_bodies_and_the_renamed_green_investment_body_follows_its_department` | ukg prefix is split into two bodies and the renamed green investment body follows its department | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_dim_organisation::test_doh_prefix_is_split_into_the_nhs_line_and_the_transport_line` | doh prefix is split into the nhs line and the transport line | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_dim_organisation::test_ehr_coding_error_in_june_2019_is_one_body_with_one_version_per_release` | ehr coding error in june 2019 is one body with one version per release | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_dim_organisation::test_the_unknown_members_exist_and_nothing_real_uses_them` | the unknown members exist and nothing real uses them | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_dim_organisation::test_an_alias_flip_does_not_start_a_version_but_a_real_rename_does` | an alias flip does not start a version but a real rename does | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_dim_organisation::test_the_23_bodies_that_moved_department_and_kept_their_prefix_keep_one_durable_key` | the 23 bodies that moved department and kept their prefix keep one durable key | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_forecast_returns::test_own_forecast_arithmetic_agrees_with_python_decimals` | Both methods recomputed in Python from the loaded rows of return n (months up to n) and the prior year's R13. | full | localdata | local full build only | none (query on the warehouse) |
| `test_independent_control::test_the_loaded_data_agrees_with_the_independent_recomputation` | the loaded data agrees with the independent recomputation | committed | - | CI (pipeline-sql) and local builds | evidence/build/file_control.csv |
| `test_model_tests::test_every_expected_sql_runs_and_agrees_with_the_committed_file_when_the_scope_is_the_same` | every expected sql runs and agrees with the committed file when the scope is the same | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_model_tests::test_ukfr_expected_is_deterministic_and_writes_the_scope` | ukfr expected is deterministic and writes the scope | full | localdata | local full build only | none (query on the warehouse) |
| `test_outturn_fact::test_the_landed_profile_rows_equal_the_file` | the landed profile rows equal the file | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_outturn_fact::test_a_unit_error_line_is_added_then_reversed_and_both_rows_are_flagged` | NHP903 X903A002, April 2023: 4.1bn in September 2023, 4.1m in December 2023. | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_outturn_fact::test_the_june_2019_period_zero_rows_are_in_the_fact_once_and_in_the_year_total` | the june 2019 period zero rows are in the fact once and in the year total | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_outturn_fact::test_the_dimension_row_counts_the_documentation_states` | the dimension row counts the documentation states | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_plan_phasing_sql::test_annual_plan_basis_reproduces_the_fy2023_24_bud_column` | Every group and measure of the profiling's consistency table that has a BUD figure comes out of | full | localdata | local full build only | none (query on the warehouse) |
| `test_plans_sql::test_estimates_measure_comes_from_the_sheet_title` | Every sheet of every Estimates workbook gets the measure the profiling read from its title; the sheet | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_plans_sql::test_the_final_plan_workbook_per_year_is_the_one_the_profiling_chose` | the final plan workbook per year is the one the profiling chose | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_plans_sql::test_pesa_department_group_sections_equal_the_profiling_inventory` | The T-SQL rules for 'which sections are department-group tables, and which measure' reproduce the | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_plans_sql::test_fy2023_24_consistency_figures_are_reproduced` | plan-sources.md section 13 (plan_consistency_2023_24.csv): the Estimates plan, the PESA 2023 plan and the | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_plans_sql::test_no_pesa_or_estimates_name_is_mapped_to_a_group_that_does_not_exist` | no pesa or estimates name is mapped to a group that does not exist | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_real_totals::test_the_real_facts_have_the_row_counts_and_sums_pinned_in_the_expectation_file` | the real facts have the row counts and sums pinned in the expectation file | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_real_totals::test_only_the_two_phasing_tables_carry_a_derived_flag_and_no_real_fact_does` | The derived tables are exactly the phasing profile and the phased plan, all rows flagged, and the real | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_register::test_each_authored_file_is_one_table_with_the_rows_of_the_file` | each authored file is one table with the rows of the file | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_register::test_the_synthetic_schemas_hold_exactly_the_registered_tables_and_no_fact_or_total_view_reads_them` | The synthetic and scale schemas hold the tables the register names and nothing else, and the only objects | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_stage_authored::test_a_file_is_loaded_into_authored_with_text_columns_and_a_description` | a file is loaded into authored with text columns and a description | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_stage_authored::test_the_committed_authored_files_are_all_loaded` | the committed authored files are all loaded | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_stage_oscar_inyear::test_planted_bad_rows_land_in_quarantine_with_their_reason` | planted bad rows land in quarantine with their reason | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_synthetic::test_the_user_map_table_has_the_rows_of_the_file_in_file_order` | the user map table has the rows of the file in file order | committed | - | CI (pipeline-sql) and local builds | none (query on the warehouse) |
| `test_synthetic::test_the_real_facts_keep_the_pinned_row_counts_and_sums_with_the_synthetic_user_map_loaded` | The map is present (so the pinned totals are measured with it loaded) and every real fact still has the rows and | committed | - | CI (pipeline-sql) and local builds | evidence/expected/real_fact_totals.csv |

<!-- inventory:end -->
