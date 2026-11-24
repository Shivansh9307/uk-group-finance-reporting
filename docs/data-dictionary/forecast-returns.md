# Data dictionary: the departments' monthly forecast returns, my own forecast and the accuracy

What `ukfr build --scope full` puts in the database for the monthly returns that departments send HM Treasury: actuals to
date plus their forecast for the rest of the year, R0 before the year to R12 during it and R13 the final outturn. Six
years, FY2017-18 to FY2022-23, 83 returns. On top of them I build my own forecast at every point and score all of it
against R13. Amounts are GBP thousands, spending positive, income negative, `DECIMAL(19,4)`. Every claim is labelled
**tested** (the test or command) or **designed** (not run).

How the sources were chosen and profiled is in [../profiling/forecast-returns.md](../profiling/forecast-returns.md) and
[../profiling/oscar-annual-extracts.md](../profiling/oscar-annual-extracts.md); this page describes what was built from
them. Everything is real data. Nothing here is synthetic or authored, and nothing mixes into another fact's total.

## Where the data comes from

| Years | Source | Returns | Source rows |
|---|---|---|---|
| FY2017-18 to FY2020-21 | the November 2022 annual extracts, one pipe-delimited member per year, Deflate64, streamed and never written to disk | R0 to R13 of each (56) | 1,721,895 + 1,828,427 + 1,886,459 + 1,821,691 in the returns, plus 72,534 period 0 rows |
| FY2021-22 | `Transparency_MFO_In_Year_data_2021-22.zip`, one csv per return | R1 to R13 (13; there is no R0) | 1,566,481 |
| FY2022-23 | `MFO_2022-23_New.zip` | R0 to R13 (14) | 1,730,442 |

The FY2021-22 extract is not read: it holds R13 and the plans only, and the MFO zip has R1 to R13 of the same year.
The two MFO files for FY2023-24 and FY2024-25 are dead links at source, so there is no departmental forecast for those
years. All are registered in the manifest; this task fetched nothing new.

## The load (stage `forecast_returns`, scope full)

`ukfr.stages.forecast_returns` reads the files through the shared readers (`oscar_extract`, `oscar_mfo`) and adds the
rows of each return up into cells at: return, month, status, type, department group, Spending Review group, organisation,
economic category, control budget (both names as written) and economic budget. Everything the load grain needs is in the
key; sub-segment, chart of accounts, usage, the accounts label and about eighty descriptive columns are summed over.
The sums are exact `Decimal`s landed in `DECIMAL(38,16)`: MFO amounts carry pence (up to nine decimal places of a
thousand) and 2,765 are written in scientific notation, such as `1.00E-13`, which needed 16 places. A cell keeps its
lineage: `source_rows`, `first_line` and `last_line`, the data record numbers inside the member (first data row = 1;
the one MFO record that a stray line break splits is rejoined by the reader and counted as one).
The cell step is the only aggregation Python does, and it changes no number: **tested**, see "Audits and the headline".

Stage time on my machine: 349 s for 10.5 million source rows when it ran alone (the four
extract members take 60 to 90 s each, the MFO zips 43 and 59 s) and 462 s inside the full build, which ran next to other
builds. Both are **tested** once; the time varies with what else the
machine is doing.

| Table | Rows | Grain |
|---|---|---|
| `raw.forecast_return_file` | 83 | one return (the 14 returns of an extract year share one member) |
| `raw.forecast_return_cell` | 2,134,610 | the cell above |
| `raw.forecast_return_expected` | 1,000 | family x year x return x period, from the independent recomputation |
| `stg.forecast_return_cell` | 2,134,610 | the same cells, typed, control budget detail mapped to the in-year spelling |
| `dw.forecast_return_org_map` | 1,411 | financial year x organisation code |
| `dw.forecast_return` | 2,116,096 (2,105,984 at periods 1 to 12, 10,112 at period 0) | financial year x return x period x organisation x economic category x control budget detail x economic budget |
| `quarantine.forecast_return_unmapped` | 17,451 cells | a cell whose organisation code has no key |
| `dw.forecast_return_header` | 83 | one return |
| `dw.forecast_return_quality` | 105 | one flag |
| `dw.forecast_own_input`, `dw.forecast_prior_profile`, `dw.forecast_own` | 55,448; 7,472; 74,256 | see "My own forecast" |
| `dw.forecast_month_compare`, `dw.forecast_accuracy` | 288,912; 24,076 | see "Accuracy" |
| `audit.forecast_return_summary`, `audit.forecast_accuracy_headline`, `audit.forecast_r13_vs_outturn` | 6, 34, 85 | see "Audits" |

(Row counts are from `table_counts.csv` of the full-scope build, copied to `evidence/full/table_counts_forecast.csv`.)

## dw.forecast_return

| Column | Meaning |
|---|---|
| `financial_year`, `return_no` (0 to 13), `period` | the return and the month: 1 = April to 12 = March; 0 = budget adjustments |
| `organisation_code`, `economic_category_code`, `control_budget_detail`, `economic_budget` | the rest of the grain; control budget detail is `DEL PROG`, `DEL ADMIN`, `DEPT AME`, `NON-DEPT AME` or `NON-BUDGET` |
| `organisation_key`, `durable_key`, `department_key` | from `dw.forecast_return_org_map` |
| `department_group_code`, `department_group_name`, `sr_group_code` | the department as the return reports it |
| `budget_measure` | `RDEL` (DEL programme or administration, resource, depreciation included as OSCAR reports it), `CDEL`, `AME` (departmental AME, both economic budgets), `OTHER` |
| `forecast_status` | `actual`, `provisional`, `forecast`, `adjustment` (see below) |
| `is_actual`, `is_provisional`, `is_period_zero`, `includes_draft` | flags |
| `amount` | the exact cell sums added and rounded once to four places |
| `source_rows`, `source_cells` | lineage: source records and cells behind the row |

A return's total is the sum of periods 1 to 12, every status, every type. Period 0 (budget adjustments; it exists in R13
of the extracts only: 3,198 + 2,557 + 2,040 + 2,317 = 10,112 rows) is kept, flagged `is_period_zero` and `adjustment`, and is
in no total. **Tested**: `sql/tests/655`.

### Actual, provisional, forecast

In return n, month m is **actual** when m <= n and **forecast** when m > n; month m = n is the month the return has just
closed and carries the label `provisional`. R0 is all forecast, R13 all actual. `is_actual` is 1 for `actual` and
`provisional`. The reason for the provisional flag is in the profiling: the month just closed moves by 6 to 31% of a
group's outturn before it settles, against 1 to 20% a month earlier. **Tested**: `sql/tests/656` recomputes the status of
every row from its return number and month.

### Statuses

In the extracts a return holds rows with status CONFIRMED and, in FY2019-20 and FY2020-21, DRAFT; the MFO files hold
Confirmed and Locked. All of them are added. **Tested**: `sql/tests/652` finds no organisation that is both DRAFT and
CONFIRMED in one return and no status outside the four.

## Loaded rows

At return x organisation x economic category x control budget detail x economic budget x month (periods 1 to 12) the load
holds **1,419,936** rows for the extracts and **703,146** for the MFO files, exactly the counts the profiling predicted
(**tested**: `sql/tests/651`). In `dw.forecast_return` the rows are fewer, because the cells of 45 organisation codes are
in quarantine (next section).

## Organisation keys and the quarantine

`dw.forecast_return_org_map` gives each (financial year, organisation code) one version and durable key of
`dw.dim_organisation` ([organisation.md](organisation.md)):

| Method | Codes | Rule |
|---|---|---|
| `in-year release` | 1,151 | the code is reported in an in-year release of that year: the version in force in the last such release |
| `code, nearest` | 254 | no release of that year reports the code (every code of FY2017-18, because the first in-year release is March 2019): the version of that code whose release range is nearest to the year |
| `prefix` | 6 | the code is not a code of the dimension but its three-letter prefix is the durable key of a body that is |

A code that none of the three can place has its cells written to `quarantine.forecast_return_unmapped` with the reason
`no organisation key`, and they are not in `dw.forecast_return`. **45 codes, 17,451 cells** are there. They are bodies
that no in-year release from March 2019 reports: the research councils that became UKRI in April 2018 (NER084, STF084,
MRC084, BRC084, EPS084, AHC084, ESR084, TST084), HEFCE (HEF022) and other bodies closed before 2019, and the
non-departmental lines that are not departments at all (England, Scotland, Wales and Northern Ireland local
authorities, the three Central Exchequer lines, the housing revenue accounts, London Underground). 16,246 of the cells are
in FY2017-18 and 914 in FY2018-19. I did not widen the rule to place them: the dimension is built from the in-year
releases, and a body that never appears in one has no version to point at. The effect is stated, not hidden: the FY2017-18
total of R13 is 868.5bn in `dw` and 870.4bn in the exact sum of all cells, and `audit.forecast_return_summary` shows both.
**Tested**: `sql/tests/654` (every cell is in `dw` or in the quarantine, the cell counts add up and so do the exact
amounts within the four-decimal rounding; no row has an Unknown key).

## Quality flags: dw.forecast_return_quality

Known bad returns are flagged, never dropped. The rules run over the data; the measure is gross (the sum of |amount|
over periods 1 to 12 of RDEL, CDEL and AME rows) against the same in R13, and the floor is GBP 1bn.

| Rule | Flags | Count |
|---|---|---|
| `u` units error | an organisation whose gross is 500 to 2,000 times its R13 gross | 5 |
| `s` scale outlier | the ratio is 20 or more and not a units error | 13 |
| `x` organisation not in the final | gross at least the floor and nothing in R13 | 15 |
| `m` department group missing | R13 gross at least the floor and no row at all in the return | 56 |
| `p` department group nearly missing | under a tenth of its R13 gross, not zero | 16 |

The five units errors: FCDO (`DID030`) R0 of FY2020-21 at 829 times its final (the case the profiling found; about
GBP 11.8 trillion of gross against GBP 14bn in R13); `MAG048` (Museums and Galleries, a DCMS sub-group) in R3 of FY2020-21 at 1,176 times; `ELC011` in R0
and R1 of FY2019-20 at 999 times; and `NCA073` (the National Crime Agency) in R1 of FY2021-22 at 850 times. The other known case, the Department of
Health missing from R1 of FY2018-19, is rule `m` on `DOH033.GROUP`. The extra findings are mine: the scale outlier
`DCM048` (DCMS core) in R3 of FY2020-21 (44 times), `ECG025` (Export Credits Guarantee Department) in every return of FY2022-23 (21 to 32 times its final: the final
restated it to 130 million), the offset line `XXX022` ("DfE Grants to Academies Offset") that carries about 23bn in every
return R0 to R12 of FY2019-20 except R9, with nothing against it in R13, and HM Treasury, which holds under a tenth of its
final gross in R0 to R9 of FY2019-20 and R0 to R3 of FY2020-21 and nothing at all in R0 of FY2017-18, FY2018-19 and FY2022-23
and in R1 of FY2021-22. I report these as flags and do not know why the returns differ from the final; they are returns I
would not score a forecast on. R13 is never flagged.
**Tested**: `sql/tests/663` recomputes every flag from `dw.forecast_return` and checks that both named cases are caught
and that every flagged department group is marked in the accuracy table.

## My own forecast

`dw.forecast_own_input` holds, for each point n (1 to 12), exactly the rows of return n for months 1 to n as return n
states them. `dw.forecast_prior_profile` holds the prior year's R13 months. `dw.forecast_own` is computed from those two
tables and from nothing else, at department group x budget measure (RDEL, CDEL, AME) x financial year x return x method x
month m = n + 1 to 12:

| Method | Forecast of month m | Defined |
|---|---|---|
| `run_rate` | the mean of the n actual months to date, year to date / n (a month with no row is zero) | n = 1 to 11 |
| `seasonal` | the prior year's R13 monthly profile scaled to the year to date: year to date x prior(m) / prior(1 to n) | n = 1 to 11, and only where the guard holds: the prior year's months 1 to n have the same sign as the year to date and are at least 10% of the absolute prior-year R13 total of the cell; none for FY2017-18, whose prior year is not in the files |

R0 has no actual month, so neither method exists for it; R12 has no month left. A fourth method, FTE x cost, is built for
the pay line only; see "The fourth method: FTE x cost, and the accuracy as modelled" below. Each row carries its lineage: `input_return_no`
(always the return itself), `input_max_period` (never above n), `input_rows`, `ytd_amount`, and for the seasonal method the
prior year and its months 1 to n. The decimal arithmetic casts to `DECIMAL(20,6)` first, because a plain product of two
`DECIMAL(19,4)` amounts exceeds 38 digits and loses scale silently.

**No-leakage tests**, **tested**: `sql/tests/660` (a) checks the lineage of every row, (b) proves that the input table
equals, in both directions, the rows of `dw.forecast_return` with return = n and month <= n, (c) proves that the prior
profile equals R13 of the prior year, and (d) recomputes both methods from that restricted set alone, reading
`dw.forecast_return` directly, and requires an exact match with `dw.forecast_own`. `sql/tests/661` pins where the
forecast exists. `pipeline/tests/test_forecast_returns.py::test_own_forecast_arithmetic_agrees_with_python_decimals` recomputes
a sample of 40 cells in Python decimals at 60 digits and agrees to within 0.0001.

### Why the seasonal method has a guard

The first version of the seasonal method had no guard and scored a WAPE of 84% to 116% in four of the five years it exists.
I looked at the ten cells with the largest absolute full-year error before changing anything
(**tested**: `tests/diagnostics/seasonal_top_errors.sql`, result before the guard in
`tests/diagnostics/seasonal_top_errors_before_guard.csv`). Money in GBP thousands, rounded:

| FY, return | Department group, budget | Year to date | Prior-year months 1 to n | Prior-year total | Share | Seasonal forecast | R13 |
|---|---|---|---|---|---|---|---|
| 2018-19 R1 | CLG085, AME | 1,910,340 | -5,730 | 15,974,741 | 0.04% | -5,325,861,557 | 21,799,203 |
| 2021-22 R9 | HMT087, AME | -37,649,548 | 261,537 | 35,153,079 | 0.7% | -5,060,460,031 | 46,184,146 |
| 2022-23 R7 | HMT087, AME | 153,384,591 | 2,133,074 | 46,184,146 | 4.6% | 3,320,998,871 | 135,544,185 |
| 2022-23 R8 | BIS084, AME | 10,546,003 | 389,292 | 111,031,076 | 0.4% | 3,007,855,442 | -78,984,217 |
| 2022-23 R1 | HMT087, AME | 1,801,542 | 32,079 | 46,184,146 | 0.07% | 2,593,680,562 | 135,544,185 |
| 2019-20 R11 | BIS084, AME | 6,761,575 | -1,009,630 | -106,507,757 | 0.9% | 713,291,193 | 9,720,206 |
| 2021-22 R10 | HMT087, AME | -14,892,802 | 867,129 | 35,153,079 | 2.5% | -603,748,514 | 46,184,146 |
| 2019-20 R10 | BIS084, AME | 6,565,762 | -1,139,050 | -106,507,757 | 1.1% | 613,936,687 | 9,720,206 |
| 2022-23 R8 | HMT087, AME | 129,085,523 | -13,052,658 | 46,184,146 | 28.3% | -456,742,576 | 135,544,185 |
| 2022-23 R10 | HMT087, AME | 147,077,050 | -15,014,774 | 46,184,146 | 32.5% | -452,396,283 | 135,544,185 |

All ten are departmental AME, and the denominator is the cause: the prior year's months 1 to n are either a tiny share of its
year (under 5% in eight of the ten) or of the opposite sign to the year to date (seven of the ten); every one of the ten fails the guard below one way or the other, so the factor
prior(m) / prior(1 to n) is huge or flips the sign of the forecast. The guard is therefore a definition, not a tuning: the
seasonal forecast exists only where the prior year's months 1 to n have the same sign as the year to date and are at least
10% of the absolute prior-year total. A cell that fails it has no seasonal forecast at all. **Tested**: `sql/tests/661` states
the rule exactly (every seasonal row obeys it and every cell that passes it has a seasonal forecast) and `sql/tests/660`
recomputes the forecast with the guard. Run again after the guard, the same query shows the two largest remaining errors in
cells that are themselves flagged (`NCA073` R1 of FY2021-22 and `DCM048` R3 of FY2020-21, units and scale errors in the
return) and, after them, departmental AME lines of HM Treasury, Health and BEIS where R13 differs greatly from the returns.

## Accuracy

`dw.forecast_month_compare` has twelve rows for every department group x budget measure x year x return x method
(`department`, `run_rate`, `seasonal`): the amount the method states for the month (the actual for months 1 to n; the
forecast for the rest) and the amount in R13. A department group that is in R13 but missing from return n counts as zero
in the return, which is how a missing department shows. `dw.forecast_accuracy` has one row per cell, return and method:

| Column | Meaning |
|---|---|
| `full_year_forecast`, `full_year_outturn`, `full_year_error` | actuals to date plus the forecast remainder, against R13; error = forecast minus outturn |
| `full_year_abs_error`, `full_year_abs_outturn` | the additive parts of WAPE |
| `wape`, `bias` | full-year absolute error and signed error as shares of |outturn|; positive bias = over-forecast |
| `fm_wape`, `fm_bias`, `fm_abs_error`, `fm_error`, `fm_abs_outturn` | the same on the forecast months only, month by month |
| `mape` | |error| / outturn, only where the full-year outturn is positive and at least GBP 100m |
| `is_flagged_return` | the department group is in `dw.forecast_return_quality` for this return |

The two versions (all returns; excluding the flagged ones) are the same table with `is_flagged_return` as the filter.
Any aggregate WAPE is a ratio of sums, never a mean of percentages. **Tested**: `sql/tests/662` recomputes the
department's forecast and my run rate for every cell by a second route, straight from `dw.forecast_return` with a different
query shape, and requires the full-year and forecast-month sums to match exactly and every ratio to equal its sums.

## Audits and the headline

`audit.forecast_return_summary` (**tested**, `sql/tests/664`; copy in `evidence/full/forecast_return_summary.csv`):

| Year | Returns | Rows (periods 1-12) | Flagged returns | R13 control difference (rows, amount) |
|---|---|---|---|---|
| FY2017-18 | 14 | 324,763 | 3 | 0, 0 |
| FY2018-19 | 14 | 345,021 | 6 | 0, 0 |
| FY2019-20 | 14 | 371,396 | 13 | 0, 0 |
| FY2020-21 | 14 | 361,658 | 4 | 0, 0 |
| FY2021-22 | 13 | 341,955 | 2 | 0, 0 |
| FY2022-23 | 14 | 361,191 | 13 | 0, 0 |

The control difference is the loaded rows and exact amount of R13 (and of every return, in `all_returns_control_amount_diff`)
against `data/audit/forecast_independent_control.csv`, which `ukfr control forecast` writes with code that shares nothing
with the readers: its own Deflate64 stream, the `csv` module, columns found by header text, its own month table.
**Tested**: `sql/tests/657` for all 83 returns and every month and period 0: difference 0 in rows and in amount; and
`dw.forecast_return` agrees with it to within the four-decimal rounding of its rows (the largest drift in a year is under
GBP 3 on 1,238bn). The independent run reads 10.5 million records and takes about nine minutes.

`audit.forecast_accuracy_headline` pools R1 to R11 and every cell of a year (**tested** build, results in
`evidence/full/forecast_accuracy_headline.csv`). Full-year WAPE and signed bias. The department column is on all its
cells; each of my methods is on the cells where it exists, and the figure in brackets is the department on those same
cells. Seasonal coverage is cells and value (sum of |outturn|) as a share of all the cells of the year; a method that does
not cover a cell is not scored on it, and the audit table shows what is left out:

| Year | Version | Department | Run rate (dept on same cells) | Seasonal (dept on same cells) | Seasonal coverage, cells / value |
|---|---|---|---|---|---|
| FY2017-18 | all returns | 12.9% / -8.0% | 23.2% / -13.2% (12.6% / -7.7%) | none: no prior year | |
| FY2017-18 | excluding flagged | 12.6% / -7.8% | 23.3% / -13.2% (12.6% / -7.8%) | none | |
| FY2018-19 | all returns | 18.3% / +9.4% | 21.4% / +11.8% (16.6% / +11.7%) | 14.2% / +4.4% (6.4% / +0.8%) | 59% / 79% |
| FY2018-19 | excluding flagged | 17.0% / +11.1% | 21.4% / +11.8% (16.6% / +11.7%) | 14.2% / +4.4% (6.4% / +0.8%) | 60% / 80% |
| FY2019-20 | all returns | 7.5% / +0.1% | 9.0% / -4.4% (7.4% / +0.1%) | 8.0% / -1.7% (6.7% / +1.0%) | 68% / 90% |
| FY2019-20 | excluding flagged | 7.0% / +1.0% | 8.4% / -4.6% (7.0% / +1.1%) | 6.5% / +0.1% (6.2% / +2.0%) | 68% / 90% |
| FY2020-21 | all returns | 13.7% / -2.1% | 19.9% / -3.3% (13.5% / -1.9%) | 18.7% / +4.8% (11.8% / -0.7%) | 68% / 89% |
| FY2020-21 | excluding flagged | 11.2% / -2.5% | 16.4% / -5.2% (11.2% / -2.5%) | 14.2% / +2.1% (9.3% / -1.4%) | 69% / 89% |
| FY2021-22 | all returns | 23.7% / -4.8% | 36.4% / -4.5% (22.4% / -3.2%) | 16.6% / +8.0% (12.5% / +5.4%) | 67% / 76% |
| FY2021-22 | excluding flagged | 17.5% / -7.6% | 27.1% / -13.2% (17.4% / -7.6%) | 10.6% / +2.7% (7.2% / +0.9%) | 68% / 77% |
| FY2022-23 | all returns | 22.9% / +10.9% | 25.2% / +8.3% (22.3% / +11.6%) | 14.3% / +7.1% (7.4% / +5.7%) | 67% / 74% |
| FY2022-23 | excluding flagged | 21.7% / +11.0% | 24.6% / +8.0% (21.6% / +11.0%) | 14.2% / +7.3% (7.3% / +5.8%) | 68% / 75% |

On exactly the same cells the department beats both simple methods in every year. The seasonal method now covers about
two thirds of the cells and three quarters to nine tenths of the value; its WAPE is lower than the run rate's mostly because
it is scored on the stabler lines (the department's own WAPE is also much lower on them), which is why the comparison with the department on the same cells is the fair one. These are WAPEs over every
department group and budget measure including departmental AME, which the profiling already showed is a poor test of
forecasting skill; the full-year DEL figures in the profiling (about 1 to 6% like for like) are on total DEL and are not
the same measure.

**R13 against the outturn dw already holds** (`audit.forecast_r13_vs_outturn`, **tested** complete and tying,
`sql/tests/659`; not a gate): for DEL, R13 is 0.3% above the year-end in-year release in FY2018-19, 3.0% above it in FY2019-20,
2.6% above in FY2020-21 and equal to it (within 0.003%) in FY2021-22 and FY2022-23; against the annual (BUD) vintages DEL
is between 0.5% below and 2.8% above. At TOTAL the in-year release is within 1.0% below and 1.5% above, and R13 is 15% to 61%
below the annual files, which carry TYPE layers that the returns hold in period 0 or not at all (profiling); I did not
break that gap down further. The FY2019-20 and FY2020-21 DEL gaps against the in-year release are the revisions the
profiling found (R13 was revised until October 2022; the June snapshot was taken before).

## The fourth method: FTE x cost, and the accuracy as modelled

**Read the FTE x cost scores with this first.** Its WAPE on the pay line (39.7% to 45.3% a year) mostly reflects that the workforce
paybill is only about 13% of the pay line it is scored against (11.7% to 14.3% a year, **tested**: `tests/dax/926`), so the method
forecasts about a seventh of what the return's pay line carries. It says little about the method on a department whose workforce is
the whole pay line; the post hoc comparison by cover band below is the only look at that.

The model reads the accuracy through `dw.v_model_forecast_accuracy` (`sql/audit/925`). Everything below is real data, scope
full, derived by the SQL named; nothing is authored or synthetic. Amounts are GBP thousands; the workforce files are in
pounds and are divided by 1,000 at the boundary, in `sql/audit/921`.

### The pay line

The pay line is economic category `A101` (the statement's line R30 Pay) of the control budget RDEL, as the returns report it:
the pay of the department group's core department and of the arm's length bodies that report to it. Departmental AME has a
little A101 too; it is not in the line. `dw.forecast_pay_input` (21,361 rows) holds the line of return n for months 1 to n as
return n states them, and `dw.forecast_pay_prior_profile` the prior year's R13 line, the same shape as the two tables of the
other methods (`sql/audit/920`). **Tested**: `sql/tests/923` rebuilds the full-year forecast and outturn of every cell and
method from `dw.forecast_return` by another route (the paybill it uses for FTE x cost is the lineage value of `dw.forecast_own_pay`; `sql/tests/921` is the test that checks that value against `dw.workforce_month`).

### The method

For a department group g, year y and return n (1 to 11), take the department of the current structure that g's department
number maps to (the number in the group code, through `dw.department_reported_number`, the rule the outturn uses) and the valid
organisation-month cells of the pay bridge for it (`dw.v_pay_cell`, `cell_status = 'valid'`; I did not redo its exclusions),
added over the department:

- FTE = the full-time equivalent of month n, the month return n has just closed (the calendar month n - 1 months after April);
- cost = the department's paybill of month n divided by its FTE (pounds per full-time equivalent per month, 16 decimal places);
- the forecast of each remaining month m = n + 1 to 12 is FTE x cost / 1,000. It is the same figure for every remaining month.

FTE x cost is algebraically the paybill of month n. I built it as the product so that the lineage shows both factors
(`workforce_fte`, `cost_per_fte_gbp`, `workforce_paybill_gbp`, `workforce_month` in `dw.forecast_own_pay`), and I say here that it
is a "last month's pay carried forward" method with no seasonality and no pay-award step. It forecasts the pay line only, is
never added to a department's total, and is scored against the pay line of R13.

No look-ahead and no gap-filling: only the workforce of month n is read, never a later month and never an earlier month standing
in for a missing one. **Tested**: `sql/tests/920` (the month read is exactly the calendar month of period n, the method
forecasts exactly the months n + 1 to 12 with one amount, and exists in no R0, R12 or FY2017-18, whose months precede the files).
`sql/tests/921` recomputes every covered cell from the raw rows of `dw.workforce_month` with a different order of operations (the
paybill added first and divided by 1,000 last, the valid cells found again from the list of excluded cells, the department by a
window function) and requires the same set of cells and the same forecasts to within 0.0001.

My run-rate and seasonal methods are built again on the pay line (`dw.forecast_own_pay`) and the department's own pay-line
forecast is read from the return, so that the four methods are compared on one line. The accuracy of the pay line is
`dw.forecast_pay_accuracy`, with the columns and construction of `dw.forecast_accuracy`.

### Coverage, per department and year

`audit.forecast_fte_cost_coverage` has 2,955 rows, one for each department group, year and return R1 to R11 that has a pay line
(copy in `evidence/full/forecast_fte_cost_coverage.csv`), and gives each one status:

| Status | Cells | Meaning |
|---|---:|---|
| `covered` | 582 | the department has valid workforce cells in month n |
| `no_workforce_cell_in_month` | 2,285 | no valid cell in the month: no file, the department is not in the source, or the year precedes the files |
| `shared_department` | 88 | another department group with a pay line answers to the same department of the current structure in the year (`FCO027` and `DID030` in FY2017-18 to FY2020-21), so the workforce cannot be split between them |
| `no_department` | 0 | the group's number maps to no department |

Departments covered in FY2018-19 to FY2022-23, with the share of the group's pay line that the workforce paybill is in month n
(`pay seen`, a ratio of sums over the covered cells of each year, from `audit.forecast_fte_cost_coverage`):

| Department | Covered cells of cells | Pay seen |
|---|---|---|
| HM Revenue and Customs | 54 of 55, all five years | 0.96 to 1.03 |
| Work and Pensions | 53 of 55, all five years | 0.92 to 0.94 |
| UK Export Finance | 41 of 50, all five years | 0.84 to 0.95 |
| Competition and Markets Authority | FY2021-22 and FY2022-23 | 0.91 and 0.96 |
| Food Standards Agency | 18 of 22, FY2021-22 and FY2022-23 | 1.09 and 1.08 |
| Environment, Food and Rural Affairs | four years; 2 and 3 cells in FY2018-19 and FY2020-21 | 0.92 to 1.07 |
| Science, Innovation and Technology (the BEIS group before 2023) | 51 of 55, all five years | 1.76 to 1.99 |
| HM Land Registry | FY2020-21 to FY2022-23 | 1.35 to 1.57 |
| Transport | 54 of 55, all five years | 0.27 to 1.69 |
| Housing, Communities and Local Government | 54 of 55, all five years | 0.47 to 0.53 |
| Defence | 48 of 52, all five years | 0.18 to 0.23 |
| Health and Social Care | 53 of 54, all five years | 0.02 to 0.03 |
| Education | 55 of 55, all five years | 0.02 to 0.03 |
| Foreign, Commonwealth and Development Office | 11 cells in FY2021-22, 2 in FY2022-23 | 0.69 and 0.54 |
| HM Treasury | 2 cells in FY2021-22 | 1.27 |
| Home Office | FY2018-19 | 0.007 |

**Tested** (`tests/dax/926`, against SQL over `dw`): the share of the pay-line cells of R1 to R11 that have the method is 19.5%,
18.2%, 19.5%, 26.7% and 24.5% for FY2018-19 to FY2022-23, and the workforce paybill is 13.1%, 11.7%, 13.0%, 14.3% and 13.1% of the
pay line it is compared with. Where the share is far below 1 (Health, Education, Defence, the Home Office) the group's return carries
arm's length bodies, schools or the armed forces that the workforce files do not cover, and the method sees a small part of the
pay line. Where it is above 1 (the BEIS group, Land Registry, Transport in FY2020-21) the workforce paybill is larger than the pay
line of the return, and I have not found out why (the return's pay line may be net of recharges or of capitalised pay). I chose no
threshold to drop either: the coverage is shown, not corrected.

### Accuracy as modelled

`Fact Forecast Accuracy (derived)` has one row for each forecast line (a budget measure total, or the pay line), department
group, budget measure, year, return and method: 33,619 rows (the 24,076 of `dw.forecast_accuracy` and the 9,543 of
`dw.forecast_pay_accuracy`). A cell has three methods on a budget measure total (department, run rate, seasonal) and four on the
pay line. `flagged_return` is the flag of `dw.forecast_return_quality` for the department group's return (rules `u`, `s`, `x`,
`m` and `p`), so "without the flagged returns" leaves out the whole group's return, not only its pay line. `common_cells` is 1 where
the cell has a score from every method of its line, and comparisons between methods use it, because the seasonal method exists on
about two thirds of the cells and FTE x cost on about a fifth of the pay-line cells. MAPE exists only on cells with an outturn of
at least GBP 100m, and its pooled form is a ratio of sums over those cells.

The department of the current structure is the department whose number is in the group code. The group `BIS084` (BEIS, DSIT from
2023) maps to the Department for Science, Innovation and Technology and `FCO027` to the Foreign, Commonwealth and Development
Office, as the outturn does; it is a mapping by number, so the BEIS group of every year sits under DSIT. Every group of the
accuracy tables maps to a department (**tested**: `sql/tests/922`).

**Tested** (`tests/dax/920` to `927`, 8 of 8 against SQL written over `dw`; `sql/tests/922` and `924`):

- every flagged return is flagged, and they change the numbers. `Flagged Return` is true for all 268 department-group returns that
  `dw.forecast_return_quality` flags in the department's own forecast, not for two; FCDO R0 of FY2020-21 and the Department of Health R1
  of FY2018-19 are the two with the largest effect, and `sql/tests/922` and `tests/dax/923` pin both as flagged. The department's own
  forecast on the budget measure totals, every cell (R0 to R12), with the flagged returns kept in and without them (test 922):

| Year | WAPE, all returns | WAPE, no flagged returns | Bias, all | Bias, without |
|---|---:|---:|---:|---:|
| FY2017-18 | 12.9% | 12.2% | -8.1% | -7.3% |
| FY2018-19 | 18.4% | 16.5% | +8.7% | +10.7% |
| FY2019-20 | 7.6% | 6.9% | +0.3% | +1.2% |
| FY2020-21 | 91.6% | 10.8% | +73.8% | -2.4% |
| FY2021-22 | 22.4% | 16.7% | -4.2% | -6.8% |
| FY2022-23 | 23.5% | 20.4% | +8.8% | +10.8% |

  FCDO R0 of FY2020-21 alone moves that year's department WAPE from 10.8% to 91.6% and its bias from -2.4% to +73.8%; the
  Department of Health missing from R1 of FY2018-19 is one of the cells that move FY2018-19 from 16.5% to 18.4%. `tests/dax/923`
  has the two cells: the FCDO R0 RDEL cell has an absolute error of GBP 7.5 trillion against an outturn of GBP 7.2bn (a cell WAPE
  of 1,045, the return keyed in pounds); the Department of Health cells have a forecast of zero (a cell WAPE of 1).
  `pipeline/tests/test_forecast_model.py` fails if the with and without figures of those two years are equal, so the tests cannot
  pass whether or not the flag works;
- the three methods on the budget measure totals, on the cells all three scored, without the flagged returns (test 921), WAPE of the
  department / run rate / seasonal: FY2018-19 6.4% / 9.2% / 14.2%, FY2019-20 6.2% / 7.1% / 6.5%, FY2020-21 9.3% / 13.4% / 14.2%,
  FY2021-22 7.2% / 14.4% / 10.6%, FY2022-23 7.3% / 13.6% / 14.2%;
- departmental AME alone, FY2021-22 (test 924): WAPE 8.0% for the department, 17.0% for the run rate, 9.5% for the seasonal method;
- the pay line, four methods, on the cells all four scored, without the flagged returns (test 925): the department's WAPE is 1.6% to
  10.4% a year, my seasonal method's 2.6% to 7.9%, my run rate's 1.7% to 9.1% and FTE x cost's 39.7% to 45.3%, with a bias of -39%
  to -45%: FTE x cost under-forecasts because the workforce paybill is a fraction of the pay line in the departments that carry most
  of it;
- the forecast-month scores and MAPE by method (test 927).

**What the pay line says, and the limit of it.** FTE x cost does not beat the department. The comparison by how much of the pay line
the workforce paybill is is **post hoc**: I chose the band 0.8 to 1.25 (inclusive) after I had seen the coverage table, and tried no
other band, so it describes those cells and is not a result I set out to test. The share is known when a forecast is made (the
workforce paybill of the last actual month over the pay line of that month). `audit.forecast_fte_cost_cover_band`
(`sql/audit/923`, copy in `evidence/full/forecast_fte_cost_cover_band.csv`) holds it for the pay-line cells of R1 to R11 that all four
methods scored outside the flagged returns, and `sql/tests/925` recomputes it from `dw.forecast_pay_accuracy` and
`dw.forecast_fte_cost_input` (**tested**). WAPE by method:

| Cover band | Cells | Department | Run rate | Seasonal | FTE x cost |
|---|---:|---:|---:|---:|---:|
| 0.8 to 1.25 | 186 | 2.4% | 2.8% | 3.5% | 3.5% |
| outside it | 311 | 6.6% | 6.5% | 4.5% | 45.4% |

Where the method sees about the whole pay line it is close to my other methods and a little behind the department; where it sees a
small part of the pay it is of no use.

## What I could not settle in the fourth method

- The workforce paybill of the BEIS group, Land Registry and Transport (FY2020-21) is larger than the pay line of the return for
  the same month; I did not trace why.
- A department that split in 2023 (BEIS into three) is mapped by number and so sits under one current department; only FY2022-23
  months before the split are in the returns, so no FTE x cost cell belongs to a successor department.
- The method carries last month's pay forward unchanged: the pay awards and bonus months that the pay bridge shows are not in it.

## What I could not settle

- The seasonal method covers about two thirds of the cells and 74% to 90% of the value of a year (the audit table has the
  exact coverage); the cells that fail its guard have no forecast from it, and a method that falls back to the run rate there
  would be a different method. I chose the 10% threshold by reading the ten worst errors, not by tuning it against the
  WAPE; a different threshold would move the coverage and the WAPE, and I have not scanned thresholds.
- The 45 quarantined codes are bodies the in-year dimension has never seen. Whether they should get a key by an authored
  mapping is a decision for whoever reads this table next.
- The flags are rules, not a judgement on the source: `HM Treasury` and `ECG025` are flagged because their returns differ
  from R13 by a large factor, and I do not know why the final restated them.
