# Departments' monthly forecast returns

Departments send HM Treasury a forecast-and-outturn return every month: R0 before the year starts
to be reported, R1 to R12 during the year, R13 the final outturn. The MFO files publish them for
FY2021-22 and FY2022-23; the November 2022 annual extracts hold the same returns for FY2017-18 to
FY2020-21 ([oscar-annual-extracts.md](oscar-annual-extracts.md), question 2). This page profiles the
MFO files and then, for all six years, tests the rule that separates actual months from forecast
months and previews the departments' own forecast accuracy.

Everything here is **tested** unless marked **designed**. Command, run on 2026-11-16:

```
UKFR_DATA_DIR=<main checkout>/data/raw uv run --project pipeline ukfr profile all --cache-dir <scratch>
```

Reader: `ukfr.readers.oscar_mfo` (tests in `pipeline/tests/test_oscar_mfo.py`, on real lines of
`MFO-R05-2022-23.csv`). Profiling: `ukfr.profile.mfo`. Every comparison below is at department group
x control budget detail x economic budget x month, built by `returns_cube`: extract years take
versions R0-R13, periods 1-12, every status; MFO years take every row.

## 6. The MFO files

Per return: [`data/audit/mfo_file_control_totals.csv`](../../data/audit/mfo_file_control_totals.csv);
totals by return, month, control budget and economic budget:
[`mfo_return_month_totals.csv`](data/mfo_return_month_totals.csv).

| | FY2021-22 | FY2022-23 |
|---|---|---|
| Zip | `Transparency_MFO_In_Year_data_2021-22.zip` | `MFO_2022-23_New.zip` |
| Returns | R01-R13 (13 files; no R00) | R00-R13 (14 files; one named `MFO-R09-202223.csv`) |
| Rows | 1,566,481 (R01 69,404 ... R13 140,805) | 1,730,442 (R00 43,229 ... R13 152,130) |
| Full-stream time | 35.7 s | 50.5 s |

- Comma-separated, 91 columns, the same column names as the annual extracts, Windows-1252.
- Every file holds all twelve months `P01` ... `P12` (`MONTH_SHORT_NAME` and `QUARTER_SHORT_NAME` both
  carry the period); `YEAR_SHORT_NAME` is `202122` / `202223`.
- `VERSION_CODE` is `Forecast` on every row; `TYPE_CODE` is `TYPE_INYEAR` on every row; `USAGE_CODE`
  is `OUTTURN` or `BOTH`; `STATUS_CODE` is `Confirmed` or `Locked` (for example R13 2021-22: 118,324
  Confirmed, 22,481 Locked). Locked rows are not duplicates of Confirmed ones and both are needed for
  the totals below. `ACCOUNTS_LONG_NAME` is empty.
- The control budget columns are the other way round from the extracts: `CONTROL_BUDGET_L0_LONG_NAME`
  holds the detail (`DEL PROG`) and `L1` the top level (`DEL`). The reader maps both layouts to the
  in-year spelling.
- `AMOUNT` is plain decimal text with fractions of a thousand (pence), unlike the extracts.
- **One broken record**: in `MFO-R05-2022-23.csv` a line break was inserted after the first field, so
  physical line 102,913 holds only `202223` and the next line starts with a comma. csv reads that as a
  1-field row and a 91-field row with an empty `YEAR_NO`. The reader rejoins them (one record repaired,
  record number 102,913) and passes any other wrong-width row through to be counted; there are none.

**R13 against the June in-year release** ([`mfo_r13_vs_inyear.csv`](data/mfo_r13_vs_inyear.csv)):

| Year | June release | DEL admin gap | DEL programme gap | Dept AME gap | Non-budget gap |
|---|---|---|---|---|---|
| 2021-22 | 2022-06 (`MFO_202122_R13_v1`) | +£12 thousand | -£20.5m | -£351.9m | +£2.40bn |
| 2022-23 | 2023-06 (`MFO_2022-23_R13_v1`) | +£23 thousand | -£2 thousand | -£13 thousand | £0 |

**Confirmed for FY2022-23** (identical to rounding in every control budget and month). **Confirmed for
DEL in FY2021-22** (£20.5m in £555bn), with £352m of departmental AME and £2.4bn of non-budget
different: the June 2022 release was cut from a slightly different R13 than the one published in the
MFO file, mainly outside DEL.

## 7. Where actuals end and forecasts begin

HMT's rule is that return n holds actuals for periods 1 to n and forecasts for the rest. I measured,
for every year, return n (0-12) and month m, how far the return's value is from final outturn (R13),
at department-group level so that offsetting errors do not hide each other: the sum over groups of
|value in return n - final| as a share of the sum of |final|. Full detail by year, return and month,
with totals and the ten largest groups: [`mfo_revision_by_month_return.csv`](data/mfo_revision_by_month_return.csv).
"Lag" is n - m: lag 0 is the month the return has just closed, lag 1 the month before, lag -1 the first
month after (a forecast under the rule). Average over the returns, per cent:

| Lag | 2017-18 | 2018-19 | 2019-20 | 2020-21 | 2021-22 | 2022-23 |
|---|---|---|---|---|---|---|
| -3 (forecast) | 33.4 | 17.5 | 10.6 | 236.9 | 34.7 | 19.6 |
| -1 (forecast) | 37.8 | 15.2 | 11.0 | 161.4 | 30.6 | 16.8 |
| **0 (month just closed)** | **30.9** | **11.7** | **5.8** | **9.8** | **29.9** | **10.1** |
| 1 | 17.6 | 5.2 | 1.7 | 19.9 | 1.7 | 4.6 |
| 2 | 7.0 | 4.2 | 0.9 | 2.4 | 1.1 | 4.1 |
| 3 | 1.8 | 3.7 | 0.6 | 2.1 | 1.0 | 1.8 |
| 6 | 1.3 | 1.1 | 0.4 | 0.3 | 0.8 | 1.8 |

(2020-21 forecasts are hundreds of per cent off because of the pandemic and the R0 units error.)

What the data says:

- **Months before the one just closed are settled**: from lag 1 or 2 the revision to final is a few
  per cent at most, and it keeps shrinking.
- **The month just closed is not settled.** At lag 0 the revision is 6-31% of the group's outturn,
  between a forecast and a settled actual, and in 2017-18 and 2021-22 it is about as large as a
  forecast's. Departments report it, but much of it is provisional.
- Per group ([`mfo_arrears_by_group.csv`](data/mfo_arrears_by_group.csv), groups over £1bn a year,
  "settled" = within 1% of final): between a third and a half of the large groups are current (most of their lag-0 months
  already within 1%), and the rest are one or two months behind. Recurring "one month in arrears":
  Education, the devolved administrations, Defence (2018-19 to 2021-22) and Transport. Health and
  Social Care "revises actuals heavily" or is two months behind in five of six years (NHS accruals),
  and so do DCMS and the Cabinet Office in most years.

**Recommended rule (designed, from this evidence): in return n, month m is labelled `actual` when
m <= n, as HMT says, and the month m = n carries a second flag, `provisional`; for the backtest the
information known at point n is every month m <= n as return n states it, never as later returns
restate it.** Labelling m = n as actual is what HMT and the department knew at the time, so it does
not leak the future; flagging it lets the report show that it will move.

Sensitivity: measured on forecast months only, the departments' error to final (sum of group
absolute errors over sum of absolute final) changes little between "actual up to n" and "actual up to
n - 1": 40.84 against 40.88 (2017-18), 20.26 against 19.15, 14.31 against 13.27, 42.37 against 40.44
(2021-22) and 23.63 against 21.91 (2022-23); only FY2020-21 moves a lot (281.7 against 246.5). So the
choice moves accuracy by one to two points in a normal year; I would report the primary rule and show the n - 1
figure once as a sensitivity.

## 8. The departments' own accuracy (preview)

Full-year forecast in each return (actual months plus forecast months, as the return states them)
against final outturn: [`mfo_forecast_accuracy.csv`](data/mfo_forecast_accuracy.csv), by scope (RDEL,
CDEL, TDEL, departmental AME), with the error in £ and %, the group-level WAPE (sum of absolute group
errors / sum of absolute group outturn), the share of final outturn covered by groups present in the
return, the groups missing, groups flagged as a units error (return more than 20 times final), and a
like-for-like error that leaves both out. Total DEL, like-for-like error % / group WAPE %:

| Year | R0 | R1 | R3 | R6 | R9 | R12 |
|---|---|---|---|---|---|---|
| 2017-18 | -1.4 / 3.3 | -1.0 / 3.8 | +0.9 / 5.1 | -1.0 / 3.7 | +0.9 / 1.6 | +0.5 / 0.9 |
| 2018-19 | -0.3 / 2.8 | +0.6 / 4.0 | +0.3 / 2.9 | +0.4 / 1.6 | +0.8 / 1.1 | +0.7 / 0.8 |
| 2019-20 | -2.2 / 4.1 | -2.2 / 4.4 | -1.6 / 2.9 | -1.5 / 3.0 | -1.9 / 3.1 | -1.0 / 1.8 |
| 2020-21 | -14.9 / 15.2 | -13.2 / 14.0 | -5.9 / 7.0 | +4.0 / 6.5 | +4.3 / 5.2 | +0.8 / 1.2 |
| 2021-22 | (no R0) | +3.8 / 7.1 | +3.7 / 5.7 | +3.5 / 5.4 | +6.4 / 8.4 | +0.3 / 0.9 |
| 2022-23 | +2.2 / 4.2 | -0.4 / 6.6 | +2.6 / 2.9 | +3.5 / 3.8 | +3.1 / 3.3 | +0.8 / 1.0 |

Positive means the forecast was above final outturn. Before the like-for-like adjustment the raw
totals are dominated by data problems: FY2020-21 R0 is +1,694% (FCDO keyed in pounds), FY2018-19 R1
is -40.8% (the return covers only 59% of final outturn: Health is missing), FY2021-22 R1 +87% and
FY2022-23 R0 and R1 about -15% (coverage 82-88%).

The pattern: **from FY2020-21 departments forecast persistent overspending relative to what they
end up spending, by 3-6% of DEL through to R9, and the gap closes only in the last quarter**; the
pre-pandemic years were within about 2% either way. Capital is worse than resource (FY2022-23 CDEL
+7.5% to +10% from R3 to R6). Departmental AME forecasts are off by 10-50% for most of the year and
are not a sensible test of forecasting skill.

Percentages on income lines and near-zero lines are meaningless (a £1m forecast against a £10k
outcome is a 9,900% error). I would (designed): compute accuracy on DEL spending scopes only, report
WAPE (sum of absolute errors over sum of absolute outturn) and signed bias in £ and as a share of the
scope total, never average per-line percentage errors, show MAPE only on aggregates whose outturn is
positive and above a floor (say £100m a year), and always state the coverage and the excluded
groups next to the number.

## 9. What the own forecast can use at point n

- **Known at point n (designed rule above):** return n's months 1 to n for the year being forecast;
  nothing from returns after n; for earlier years, their final outturn (R13). Return n's own forecast
  months are the departments' forecast, the benchmark, not an input.
- **Monthly outturn for seasonality** ([`mfo_outturn_history.csv`](data/mfo_outturn_history.csv)):
  12 months of final outturn for FY2017-18 to FY2021-22 from the extracts' R13 (restated to November
  2022), and 12 months for FY2018-19 to FY2025-26 from the June in-year releases (snapshots: FY2019-20
  is R12, the others R13). So a backtest year from FY2018-19 on has at least one prior year of
  monthly outturn, and FY2017-18 has none in my files (its seasonality would have to come from later
  years, which is leakage and should not be done). The in-year releases carry year-to-date actual
  months only (R4: April-June, R7: April-September ...), never forecast months, so they add nothing
  to the forecast benchmark after FY2022-23.
- FY2023-24 and FY2024-25 MFO files are dead links, so there is no departmental forecast for those
  years; the own forecast can still be run and scored against their outturn.

## Decisions this supports

- GO: six backtest years, FY2017-18 to FY2022-23, 83 returns in all (56 in the extracts, 27 in the MFO files), each with 12 months.
- GO: MFO R13 equals the June in-year release: FY2022-23 to £23 thousand; FY2021-22 DEL to £20.5m
  (AME £352m, non-budget £2.4bn apart).
- Rule: in return n, months m <= n are actual, m = n is also flagged provisional (lag-0 revision
  6-31% against 1-20% at lag 1 and under 5% from lag 2); switching to m <= n - 1 moves forecast-month
  WAPE by one to two points except FY2020-21.
- Accuracy is reported on DEL as WAPE and signed bias with coverage stated; early returns need the
  like-for-like adjustment (coverage 59-100%, one units error of 1,000 times).
- Departments over-forecast DEL by 3-6% until R9 in FY2020-21 to FY2022-23.

## What I would change in the design

- The plan expects two backtest years for certain; the data gives six. The forecast pages and the
  no-leakage test should be built for six.
- The plan treats "actual" as one state. Add the `provisional` flag for m = n: the month just closed
  moves by 6-31% at group level, which a reader comparing "actual to date" across returns would
  otherwise take for a forecast change.
- Add a returns quality table (missing groups and units errors per return) to the data controls page;
  without it the raw R0/R1 accuracy figures are nonsense.
- WAPE and bias only, as the plan says; I would drop MAPE on departmental AME entirely.
