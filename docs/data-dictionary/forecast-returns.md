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
| `dw.forecast_own_input`, `dw.forecast_prior_profile`, `dw.forecast_own` | 55,448; 7,472; 84,049 | see "My own forecast" |
| `dw.forecast_month_compare`, `dw.forecast_accuracy` | 304,092; 25,341 | see "Accuracy" |
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
| `seasonal` | the prior year's R13 monthly profile scaled to the year to date: year to date x prior(m) / prior(1 to n) | n = 1 to 11, and only where the prior year's months 1 to n do not sum to zero; none for FY2017-18, whose prior year is not in the files |

R0 has no actual month, so neither method exists for it; R12 has no month left. A forecast from the FTE times cost-per-FTE
is not built here: it needs the workforce data and a later task adds it. Each row carries its lineage: `input_return_no`
(always the return itself), `input_max_period` (never above n), `input_rows`, `ytd_amount`, and for the seasonal method the
prior year and its months 1 to n. The decimal arithmetic casts to `DECIMAL(20,6)` first, because a plain product of two
`DECIMAL(19,4)` amounts exceeds 38 digits and loses scale silently.

**No-leakage tests**, **tested**: `sql/tests/660` (a) checks the lineage of every row, (b) proves that the input table
equals, in both directions, the rows of `dw.forecast_return` with return = n and month <= n, (c) proves that the prior
profile equals R13 of the prior year, and (d) recomputes both methods from that restricted set alone, reading
`dw.forecast_return` directly, and requires an exact match with `dw.forecast_own`. `sql/tests/661` pins where the
forecast exists. `pipeline/tests/test_forecast_returns.py::test_own_forecast_arithmetic_agrees_with_python_decimals` recomputes
a sample of 40 cells in Python decimals at 60 digits and agrees to within 0.0001.

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
`evidence/full/forecast_accuracy_headline.csv`). Full-year WAPE and bias, each method on all its cells:

| Year | Version | Department WAPE / bias | Run rate | Seasonal |
|---|---|---|---|---|
| FY2017-18 | all returns | 12.9% / -8.0% | 23.2% / -13.2% | none (no prior year) |
| FY2017-18 | excluding flagged | 12.6% / -7.8% | 23.3% / -13.2% | none |
| FY2018-19 | all returns | 18.3% / +9.4% | 21.4% / +11.8% | 84.5% / -33.6% |
| FY2018-19 | excluding flagged | 17.0% / +11.1% | 21.4% / +11.8% | 84.5% / -33.6% |
| FY2019-20 | all returns | 7.5% / +0.1% | 9.0% / -4.4% | 48.0% / +7.4% |
| FY2019-20 | excluding flagged | 7.0% / +1.0% | 8.4% / -4.6% | 51.5% / +10.9% |
| FY2020-21 | all returns | 13.7% / -2.1% | 19.9% / -3.3% | 24.0% / +4.6% |
| FY2020-21 | excluding flagged | 11.2% / -2.5% | 16.4% / -5.2% | 20.1% / +2.2% |
| FY2021-22 | all returns | 23.7% / -4.8% | 36.4% / -4.5% | 89.1% / -57.0% |
| FY2021-22 | excluding flagged | 17.5% / -7.6% | 27.1% / -13.2% | 83.9% / -62.1% |
| FY2022-23 | all returns | 22.9% / +10.9% | 25.2% / +8.3% | 116.2% / +65.3% |
| FY2022-23 | excluding flagged | 21.7% / +11.0% | 24.6% / +8.0% | 116.3% / +65.2% |

The audit table also carries `dept_wape` and `dept_bias`, the department's own forecast on exactly the cells where each
of my methods exists; they are within 2 points of the first column in every row. The department beats either simple
method in every year and the seasonal method is the worst in every year. I think the reason is that it multiplies the year
to date by a prior-year profile whose early months can be tiny, so a small denominator blows the forecast up, but I have
not tested that. I did not tune it. These are WAPEs over every department
group and budget measure including departmental AME, which the profiling already showed is a poor test of forecasting
skill; the full-year DEL figures in the profiling (about 1 to 6% like for like) are on total DEL and are not the same
measure.

**R13 against the outturn dw already holds** (`audit.forecast_r13_vs_outturn`, **tested** complete and tying,
`sql/tests/659`; not a gate): for DEL, R13 is 0.3% above the year-end in-year release in FY2018-19, 3.0% above it in FY2019-20,
2.6% above in FY2020-21 and equal to it (within 0.003%) in FY2021-22 and FY2022-23; against the annual (BUD) vintages DEL
is between 0.5% below and 2.8% above. At TOTAL the in-year release is within 1.0% below and 1.5% above, and R13 is 15% to 61%
below the annual files, which carry TYPE layers that the returns hold in period 0 or not at all (profiling); I did not
break that gap down further. The FY2019-20 and FY2020-21 DEL gaps against the in-year release are the revisions the
profiling found (R13 was revised until October 2022; the June snapshot was taken before).

## What I could not settle

- Seasonal accuracy depends on a profile that can be tiny in the first months; I report it as specified and did not add a
  guard. A guard (for example, fall back to the run rate when the prior year's months 1 to n are under a tenth of the
  year) would be a design change, not a fix.
- The 45 quarantined codes are bodies the in-year dimension has never seen. Whether they should get a key by an authored
  mapping is a decision for whoever reads this table next.
- The flags are rules, not a judgement on the source: `HM Treasury` and `ECG025` are flagged because their returns differ
  from R13 by a large factor, and I do not know why the final restated them.
