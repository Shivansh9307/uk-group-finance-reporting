# OSCAR annual extracts (November 2022 release)

The November 2022 annual release carries one extract per year, FY2017-18 to FY2021-22. I read
every row of all five as a stream (nothing is extracted to disk) and counted what is in them. This
page answers what the plan fact and the forecast backtest need to know.

Everything here is **tested** unless it says **designed**: it was produced by

```
UKFR_DATA_DIR=<main checkout>/data/raw uv run --project pipeline ukfr profile all --cache-dir <scratch>
```

on 2026-11-16, which writes the CSVs under [`docs/profiling/data/`](data/) and
[`data/audit/`](../../data/audit/). The cache only stores each file's full-stream scan so the
reports can be rebuilt without reading 12 GB again; a run without it reads everything from the zips.
The readers are `ukfr.readers.oscar_extract` (tests in `pipeline/tests/test_oscar_extract.py`, on four
real lines of the 2021-22 extract) and the profiling code is `ukfr.profile.extract`.

## The files

| File | Zip method | Member size | Rows | Amount total (£000) | Full-stream time |
|---|---|---|---|---|---|
| `2022_OSCAR_Extract_2017_18.zip` | Deflate64 | 2,893,892,212 | 1,744,545 | 16,146,488,327 | 69.3 s |
| `2022_OSCAR_Extract_2018_19.zip` | Deflate64 | 3,096,842,387 | 1,861,197 | 14,860,630,472 | 92.8 s |
| `2022_OSCAR_Extract_2019_20.zip` | Deflate64 | 3,188,249,483 | 1,917,436 | 16,081,680,665 | 84.2 s |
| `2022_OSCAR_Extract_2020_21.zip` | Deflate64 | 3,068,373,810 | 1,851,356 | 30,249,606,432 | 74.0 s |
| `2022_OSCAR_Extract_2021_22.zip` | deflate | 278,351,016 | 167,709 | 4,558,273,247 | 6.3 s |

Source: [`data/audit/extract_file_control_totals.csv`](../../data/audit/extract_file_control_totals.csv).
The times are wall-clock for one sequential run of the scan on my machine (decompress, parse 91
fields, aggregate in `Decimal`), one file at a time. The amount total is the plain sum of every row,
which double counts across versions; it is a control figure for the file, not a spending total.

Format facts, all confirmed on every row:

- Pipe-delimited, every field quoted, 91 columns on every row (0 rows of another width in all five files).
- Encoding is Windows-1252, not UTF-8: the 2021-22 file has 0x92 (a curly apostrophe). Reading it as
  UTF-8 fails.
- `AMOUNT` is £000 as fixed-width text: a sign or a space, zero padding and a trailing point
  (`" 000000000005000."`, `"-000000000000336."`). No row has digits after the point.
  `Decimal(text.strip())` reads it exactly.
- `MONTH_SHORT_NAME` is `Apr-17` ... `Mar-18` for periods 1 to 12 and `Period 0 - 17-18` for period 0.
  No file has a period 13.
- Each file holds one `YEAR_SHORT_NAME` only.

One pitfall I hit: `ukfr.zipstream.open_text` re-slices its buffer on every read. A Deflate64 member
inflates to chunks of 30 MB or more, so that is quadratic: the 278 MB file took 108 seconds to read
line by line through it. The extract reader therefore wraps `zipstream.iter_member` in its own
offset-based reader (`oscar_extract.text_stream`), which reads the same file in about 6 seconds. I
did not change `zipstream.py` because another task owns it; the fix there is three lines.

## 1. Rows by version, period and status

Full counts and sums: [`extract_version_period_status.csv`](data/extract_version_period_status.csv)
(994 rows: year x version x period x status). Completeness by version:
[`extract_return_completeness.csv`](data/extract_return_completeness.csv).

| Year | Versions present | Months 1-12 in each return | Statuses |
|---|---|---|---|
| 2017-18 | PLANS, R0 to R13 | 12 in every return R0-R13; R13 also has period 0 | CONFIRMED only |
| 2018-19 | PLANS, R0 to R13 | 12 in every return | CONFIRMED only |
| 2019-20 | PLANS, R0 to R13 | 12 in every return | CONFIRMED; DRAFT rows in R1-R12 |
| 2020-21 | PLANS, R0 to R13 | 12 in every return | CONFIRMED; DRAFT rows in R0-R12 |
| 2021-22 | PLANS, R13 | 12 in R13 | CONFIRMED only |

PLANS rows are all period 0. The `DATA_EFFECTIVE_DATETIME` of each return is a single load moment that
runs from late April (R0) to late April the following year (R12), about one a month, which is the
monthly forecast-and-outturn cycle (for example 2018-19: R0 2018-04-24, R1 2018-05-21, ...,
R12 2019-04-25). R13 rows carry many load dates, the latest in October 2022: R13 kept being revised
after the year closed, which matters for question 3.

The earlier sample of the FY2021-22 file reported R13 147,708 rows and PLANS 19,869 rows; the full
count is R13 147,813 and PLANS 19,896. The older vintage's PROPOSED status does not appear in the
November 2022 files at all.

## 2. GO/NO-GO: complete monthly returns for FY2017-18 to FY2020-21

**GO for all four years.** Each of FY2017-18, FY2018-19, FY2019-20 and FY2020-21 has every return
R0, R1, ..., R12 and R13, and every return carries all twelve months, the same shape as the MFO files
for FY2021-22 and FY2022-23. With the MFO years that gives **six complete years of departments' own
monthly forecasts, FY2017-18 to FY2022-23**, not two. FY2021-22 is the exception inside this release:
its extract holds R13 and Plans only, so its returns come from the MFO file.

Two things the backtest has to deal with (details in [forecast-returns.md](forecast-returns.md)):

- **DRAFT rows.** In FY2019-20 and FY2020-21 some organisations' rows in a return are DRAFT (for
  example 34 organisations in 2019-20 R1, 49 in R12). I checked whether this double counts: in no
  return does an organisation have both DRAFT and CONFIRMED rows, and no key (organisation, sub-segment,
  economic category, control budget, economic budget, month) appears under both. So in this vintage a
  return's total is the sum of every status, and dropping DRAFT would drop those organisations.
  HMT's warning about summing across statuses applies to the older vintage that also had PROPOSED
  rows; a loader test should assert the "one status per organisation per return" rule rather than
  trust it.
- **Bad early returns.** Early returns are incomplete or wrong in places: FY2020-21 R0 states the
  Foreign, Commonwealth and Development Office at £10.17 trillion (pounds keyed as thousands, about
  1,000 times its R13 of £9.96bn), and FY2018-19 R1 has no Department of Health rows. These are in the
  source; the accuracy measures report them and leave them out of a like-for-like figure.

## 3. Which layers make a correct total

The rule that reproduces the in-year releases is: **for a return, take periods 1-12, every status,
every type, both `ACCOUNTS_LONG_NAME` values (TRIAL BALANCE and ADDITIONAL INFORMATION). Leave out
period 0.** Evidence ([`extract_layers.csv`](data/extract_layers.csv)):

- Periods 1-12 of every return hold `TYPE_INYEAR` rows only. Every other type (`TYPE_NEUTRAL`,
  `TYPE_SWITCH`, `TYPE_MOG`/`TYPE_MOGDISAG`, `TYPE_OUTTURN`, `TYPE_BCT` ...) sits in period 0 of R13
  and in PLANS. Period 0 of R13 is mostly budget-neutral and machinery-of-government movements that
  net to about zero inside DEL but not inside NON-BUDGET and AME (2018-19: £810bn of budget-neutral
  NON-BUDGET additional-information rows alone). The in-year releases carry no period 0 (June 2019 has 71 rows of it).
- Dropping ADDITIONAL INFORMATION is wrong: TRIAL BALANCE only misses the June releases by £15bn to
  £44bn in DEL programme. Taking all accounts gets within the figures below.

R13 (FY2019-20: also R12, because the June 2020 release is `RETURN12_APR`, not R13) against the June
in-year release, months 1-12, £000 ([`extract_r13_vs_inyear.csv`](data/extract_r13_vs_inyear.csv),
by department group in [`extract_r13_vs_inyear_del_by_group.csv`](data/extract_r13_vs_inyear_del_by_group.csv)).
The in-year totals are computed inline from the committed current-layout releases; I did not write
an in-year reader:

| Year | Extract version | June release (its version) | DEL admin gap | DEL programme gap | Dept AME gap |
|---|---|---|---|---|---|
| 2018-19 | R13 | 2019-06 (OUTTURN) | +17,169 (0.17%) | +1,308,982 (0.34%) | +243,472 (0.10%) |
| 2019-20 | R12 | 2020-06 (RETURN12_APR) | +204,534 (1.91%) | +8,448,903 (2.05%) | +424,677 (0.10%) |
| 2019-20 | R13 | 2020-06 (RETURN12_APR) | -256,373 (-2.40%) | +13,147,506 (3.18%) | -29,668,113 (-6.98%) |
| 2020-21 | R13 | 2021-06 (OUTTURN) | +1,675 (0.01%) | +15,213,983 (2.70%) | +2,284,497 (0.43%) |
| 2021-22 | R13 | 2022-06 (MFO R13 v1) | -75 (0.00%) | -20,587 (0.00%) | -351,867 (-0.06%) |

- **FY2021-22 ties**: DEL is within £21m of £555bn. This extract's R13 is the same data as the
  MFO R13 file to rounding (the MFO file carries pence; the extract whole £000).
- **FY2020-21** is off by £15.2bn in DEL programme, and £14.4bn of it is one organisation, MHCLG local
  government (`LGV085`: £21.3bn in the extract, £6.8bn in the June 2021 release). The extract's R13
  was revised up to October 2022; the June 2021 release is a snapshot taken a year and a half earlier.
- **FY2019-20** R12 is off by about £650m in every month, which is two organisations: Ministry of
  Justice core (`MOJ047`, +£4.45bn) and Department for Education core (`DFE022`, +£3.06bn). Both
  versions are R12, so this is a restatement of the return after the June 2020 snapshot, not a layer
  I have left out.
- **FY2018-19** is within 0.34%.

So the rule is right (FY2021-22 proves it exactly), and the gaps in earlier years are revisions the
annual extract carries and the quarterly snapshot does not. That is the restatement story the plan
already describes; the model should take R13 from the extract as final outturn for these years, not
the June release.

## 4. Plans

Totals by year, department group, control budget and economic budget:
[`plan_oscar_totals.csv`](data/plan_oscar_totals.csv). Summary, £bn:

| Year | Control budget | Economic budget | Plans | R13 months 1-12 | R13 period 0 | Plans minus R13 months |
|---|---|---|---|---|---|---|
| 2017-18 | DEL ADMIN | RESOURCE | 10.5 | 9.4 | -0.1 | 1.1 |
| 2017-18 | DEL PROG | RESOURCE | 329.3 | 318.3 | 1.3 | 11.0 |
| 2017-18 | DEL PROG | CAPITAL | 57.6 | 55.1 | -0.3 | 2.5 |
| 2018-19 | DEL ADMIN | RESOURCE | 11.0 | 10.0 | 0.1 | 1.0 |
| 2018-19 | DEL PROG | RESOURCE | 333.2 | 319.8 | -0.4 | 13.5 |
| 2018-19 | DEL PROG | CAPITAL | 64.6 | 62.2 | -0.4 | 2.4 |
| 2019-20 | DEL ADMIN | RESOURCE | 11.7 | 10.4 | -0.1 | 1.2 |
| 2019-20 | DEL PROG | RESOURCE | 358.7 | 356.1 | 2.1 | 2.6 |
| 2019-20 | DEL PROG | CAPITAL | 72.0 | 69.8 | -0.4 | 2.1 |
| 2020-21 | DEL ADMIN | RESOURCE | 12.7 | 11.5 | -0.6 | 1.2 |
| 2020-21 | DEL PROG | RESOURCE | 525.1 | 486.0 | -5.3 | 39.1 |
| 2020-21 | DEL PROG | CAPITAL | 99.3 | 93.6 | 0.7 | 5.7 |
| 2021-22 | DEL ADMIN | RESOURCE | 13.4 | 11.9 | -0.1 | 1.6 |
| 2021-22 | DEL PROG | RESOURCE | 476.6 | 451.6 | 0.5 | 25.0 |
| 2021-22 | DEL PROG | CAPITAL | 98.2 | 92.1 | -0.1 | 6.1 |

DEL programme plans sit 0.7-8% above outturn every year and DEL admin 10-13%, as a final budget
should (departments underspend their limits). Departmental AME plans are 10-30% above outturn in
resource and 18-100% in capital, which is what AME forecasts look like and
why AME variance should not be presented as budget performance. Plans cover 63-64 department groups
a year, the same groups as R13.

**Fill rates** ([`plan_oscar_grain_fill_rates.csv`](data/plan_oscar_grain_fill_rates.csv), all 91 columns,
Plans and R13 side by side, with distinct counts for the grain columns). Plans rows fill the same
columns as R13 rows: organisation, sub-segment, economic category and chart of accounts are 100%
populated on both. The differences are in the national-accounts mappings (`TES_CODE`, `ESA_*`,
`ESTIMATES_ROW_*` are 14-16 points less filled on Plans, for example 2021-22 `TES_CODE` 66.2% against
81.3%) and in `COUNTER_ORGANISATION_CODE` (5.5% on Plans, 0.1% on R13 in 2019-20).

**Distinct values**, Plans against R13:

| Year | Organisations | Sub-segments | Economic categories | Economic groups | Chart of accounts L5 |
|---|---|---|---|---|---|
| 2017-18 | 256 / 255 | 2,150 / 2,433 | 113 / 122 | 68 / 70 | 291 / 497 |
| 2018-19 | 272 / 250 | 2,412 / 2,390 | 115 / 123 | 70 / 72 | 299 / 499 |
| 2019-20 | 279 / 249 | 2,523 / 2,420 | 120 / 123 | 72 / 72 | 302 / 497 |
| 2020-21 | 265 / 248 | 2,209 / 2,509 | 121 / 125 | 71 / 72 | 303 / 504 |
| 2021-22 | 249 / 247 | 2,103 / 2,308 | 119 / 123 | 71 / 72 | 308 / 500 |

This contradicts the way the plan phrases it. Plans are **not** held on fewer columns or on a much
shorter list of codes: they use nearly as many organisations, sub-segments and economic categories
as outturn (only the chart of accounts is clearly coarser, about 300 accounts against 500, because
Plans post to "PLANS ACCOUNTS" lines). What makes them coarse is how the money is spread: inside an
organisation, a plan is put on a few categories and outturn lands on many others. The test that
matters is how much variance a report would show at each grain when nothing is really wrong
([`plan_oscar_grain_match.csv`](data/plan_oscar_grain_match.csv), DEL only, R13 all periods):

| Grain | Plan keys / outturn keys (2021-22) | Outturn on keys that have a plan | Sum of absolute variances / absolute outturn (2017-18 to 2021-22) |
|---|---|---|---|
| department group x control budget | 88 / 85 | 100% | 3.7% to 8.8% |
| department group x control budget x economic budget | 130 / 129 | 100% | 4.1% to 8.9% |
| organisation x control budget x economic budget | 443 / 456 | 99.96% | 5.4% to 11.0% |
| organisation x control budget x economic budget x economic group | 1,439 / 1,946 | 97.4% | 19.3% to 37.5% |
| organisation x control budget x economic budget x economic category | 1,709 / 2,488 | 95.9% | 22.0% to 39.4% |
| organisation x sub-segment x economic category | 4,495 / 6,909 | 91.9% | 29.7% to 47.8% |

Up to organisation x control budget x economic budget, the variance is the real underspend (5-11%).
One step finer, at economic group, it jumps to 19-38% of outturn, and most of that is allocation noise.

**Design decision this supports:** OSCAR Plans (FY2017-18 to FY2021-22) are compared with outturn at
**year x organisation x control budget detail (DEL programme, DEL admin, departmental AME) x economic
budget (resource, capital)**, and no finer. The grain guard blanks Plan whenever economic group,
economic category, sub-segment or month is in the filter context; "Plan (phased)" is the only plan
measure below that grain. This is one level coarser than the plan's "organisation x control budget x
economic group".

## 5. Rows a load would hold

At return x organisation x economic category x control budget detail x economic budget x month
([`extract_load_row_counts.csv`](data/extract_load_row_counts.csv); Plans have period 0 only, so a
plan row is year x organisation x economic category x control budget x economic budget):

- **(a) Plans for FY2019-20 to FY2021-22 only:** 3,225 + 2,885 + 2,792 = **8,902 rows**
  (7,380 if keys that net to zero are dropped). At the coarser grain recommended above it is 1,316
  DEL rows (organisation x control budget x economic budget).
- **(b) All forecast returns for every complete extract year (FY2017-18 to FY2020-21, R0-R13):**
  340,874 + 345,834 + 371,493 + 361,735 = **1,419,936 rows** (1,415,140 non-zero), from 7,258,472
  source rows. Adding the two MFO years at the same grain is 703,146 more (13,932 to 28,866 keys a return, 27
  returns, [`data/audit/mfo_file_control_totals.csv`](../../data/audit/mfo_file_control_totals.csv)).
  2.1 million rows is comfortable for Import.

## Decisions this supports

- GO: the forecast backtest covers **six years, FY2017-18 to FY2022-23**: all 14 returns (R0-R13),
  12 months each, are in the extracts for FY2017-18 to FY2020-21 (1,419,936 rows at load grain) and
  in the MFO files for FY2021-22 and FY2022-23.
- GO: a return's total is periods 1-12 across all statuses and both account types; FY2021-22 R13
  reproduces the June 2022 release to £21m in £555bn of DEL.
- GO: R13 in the extract is final outturn for FY2017-18 to FY2021-22; it differs from the June
  snapshots by up to 2.7% of DEL programme (FY2020-21, one MHCLG organisation) because it was revised
  until October 2022.
- NO-GO for comparing OSCAR Plans below organisation x control budget x economic budget: variance noise
  rises from 5-11% to 19-38% of outturn at economic group.
- Load sizes: Plans FY2019-20 to FY2021-22 = 8,902 rows; returns FY2017-18 to FY2020-21 = 1,419,936 rows.

## What I would change in the design

- The plan says the backtest covers two years for certain and more only if complete return sets turn
  up. They did: change it to six years, FY2017-18 to FY2022-23, and load the extract returns
  (1.42 million rows) as well as the MFO files.
- The plan holds OSCAR Plans at organisation x control budget x economic group. The data argues for
  organisation x control budget detail x economic budget; economic group adds noise, not information.
- "Plans are held at a coarser grain" should read "Plans are allocated differently below organisation
  level": the columns are populated, so a reader seeing a Plan value at economic category would trust
  it. The grain guard has to be explicit for that reason.
- A loader test should assert that no organisation appears under two statuses in one return, and
  quarantine any organisation-return whose total is more than 20 times its R13 (the FY2020-21 R0 FCDO
  row).
- `ukfr.zipstream.open_text` should get the offset-based buffer; until then, readers of large members
  should use `oscar_extract.text_stream`.
