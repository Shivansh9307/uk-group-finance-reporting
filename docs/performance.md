# Performance: the two slow measures, before and after

This page holds the performance evidence for the semantic model: two measures written in the plain form a report author
would write, timed and traced, then rewritten and timed and traced again in the same Desktop session, with the results
side by side. Every claim is labelled **tested** (with the command and the result file) or **designed**. The timings rank
queries against each other on one machine; they are not absolute figures and say nothing about the Power BI service, which
I do not use.

The short version: the rank by year-to-date variance % is about 40% faster on a cold cache (259 to 154 ms for one year,
203 to 111 ms for three years) because the rewrite asks the storage engine for roughly half as many scans. The as-at
measure did not get faster. I tried three forms; none differed from the plain one by more than the run-to-run and
order effect, and the trace shows why (below). I did not find a model change that makes the model smaller. Slow measure 3, the weighted allocation, has the lower median in every cell and both orders, by a few milliseconds on a 108-row bridge (section below).

## What is measured

| Measure | Where | Plain form (kept hidden, `(naive)`) | Rewrite (takes the original name) |
|---|---|---|---|
| `Outturn as at Release` (slow measure 1) | `Fact Outturn`, folder Restatement | `CALCULATE ( [Outturn], FILTER ( ALL ( 'Release' ), 'Release'[Release Sequence] <= AsAt ) )` | `CALCULATE ( [Outturn], REMOVEFILTERS ( 'Release' ), 'Release'[Release Sequence] <= AsAt )`, a column filter instead of a table filter |
| `Department Group Rank (YTD Variance %)` (slow measure 2) | `Fact Outturn`, folder Plan\Ranking | `RANKX` over the Spending Review groups of a `CALCULATE` that applies the Variance % item of Scenario Comparison and the YTD item of Time Intelligence, written three times (the guard, the table filter and the value) | the value of each group worked out once in `ADDCOLUMNS` over `ALLSELECTED ( 'Spending Review Group' )`, filtered to the groups that have one, and `RANKX ( Groups, [@ytd], YtdVariancePercent, DESC, SKIP )` over that column |
| `Allocated Amount` (slow measure 3) | `Allocation Bridge (derived)`, folder Allocation | `SUMX` over each department and pool of the bridge with a nested `CALCULATE` for the pool and one for the weight (hidden `Allocated Amount (naive)`) | `SUM` of the stored allocated amount, one pass over the bridge |

The plain forms are still in the model as hidden measures `Outturn as at Release (naive)` and
`Department Group Rank (YTD Variance %) (naive)`, display folder `Performance\Naive`, with a description that says they are
kept as evidence. They are in no perspective and no other measure reads them (**tested**:
`pipeline/tests/test_model_measures.py`). The rewrites kept the original names, so the report visuals and the older DAX
tests did not change.

The rank ranks Spending Review groups and not departments of the current structure, because the plan is published by group
and `Plan` is BLANK for a selection of a department (the grain guard): a rank of the year-to-date variance % over
departments would be BLANK everywhere. The year-to-date variance % exists only at period 12 or for a whole year, because a
year-to-date window before the year end is never a published plan period (`docs/model.md`, Time Intelligence), so the rank
queries hold period 12 or whole years.

## Same results

**Tested**: tests 810 to 813 return the plain form and the rewrite side by side with their difference, over the grids of the
perf queries, and compare both with T-SQL (`docs/model-testing.md`). Result files: `tests/results/810_*.csv` to
`813_*.csv`. `ukfr dax-compare` passes all of them, with the largest absolute difference 0 for the as-at measure (151, 1,931
and, summarised by release, 9,065 cells) and 0.000001 parts per million for the ranks (92 cells, the 23 of 2024-25 at period
12 and 69 for three years). The difference column of every row is 0.

Not tested: ties. No two groups share a variance % in the data, so `RANKX` with `SKIP` on equal values is the same function
in both forms but is not exercised here.

## Setup, and how the files were made

- Power BI Desktop, Microsoft Store build 2.159.1231.0, the model `model/UKGroupFinance.pbip` open in it, Import mode,
  compatibility level 1702, full-scope warehouse (`Fact Outturn` 658,554 rows). Nothing else was queried during a run, and
  Desktop was refreshed first with `tools/run_dax.ps1 -Refresh`.
- Queries: `tests/perf/*.dax` call the original measure names (the rewrites), `tests/perf/naive/*.dax` are the same
  queries on the `(naive)` measures, so before and after run the same query text. The two rank queries now carry the filter the report page
  puts on the plan: `'Fact Plan'[Plan Measure]` in `RDEL_EX_DEPN` and `CDEL`, the DEL headline. Because the rank queries
  changed, the plain forms were timed again with the changed queries (the first baseline, 293 and 241 ms cold for the two
  rank queries, was on the queries without the filter and is replaced; the as-at queries did not change).
- Timings: `powershell.exe -NoProfile -File tools/run_dax.ps1 -QueryDir tests/perf/naive -OutDir evidence/perf/naive -Benchmark -Cold 5 -Warm 5`
  and the same with `-QueryDir tests/perf -OutDir evidence/perf/rewrite` (`dscmd benchmark`: five runs with the cache
  cleared, then five warm), then `python tools/summarise_benchmarks.py --dir <folder>` for each. One CSV per query holds every run
  and `summary.csv` the median, minimum and maximum of the total duration
  ([naive](../evidence/perf/naive/summary.csv), [rewrite](../evidence/perf/rewrite/summary.csv)). `-Benchmark` writes into `-OutDir` only; the
  files in `tests/results` are untouched.
- **Order check.** In the first pass the plain forms ran first and the rewrites second. Because that can favour the first set
  (the engine and Desktop warm up and drift over a session), I ran both again in the opposite order, rewrites first
  ([second_pass/rewrite](../evidence/perf/second_pass/rewrite/summary.csv), [second_pass/naive](../evidence/perf/second_pass/naive/summary.csv)).
- Traces: `powershell.exe -NoProfile -File tools/trace_query.ps1 -QueryFile <query> -OutDir <scratch folder> -Cold`
  once per query and per form, then `python tools/compact_traces.py <scratch folder> evidence/perf/<naive|rewrite>/traces`.
  The full traces run to megabytes, so what is committed is the compact form: counts and times, the ten longest
  storage-engine queries with their text, the most repeated one, and the first 40 lines of the logical and physical plans with
  the length of the whole plan ([naive](../evidence/perf/naive/traces/), [rewrite](../evidence/perf/rewrite/traces/)). The
  script removes drive paths and this machine's name and account and stops if one is left. The storage-engine queries that
  carry a callback to the formula engine (text `CallbackDataID`) were counted in the full traces and are quoted below.
- Two things about the tool. Some `dscmd` runs lose their trace events (see `runs_with_events` in each summary): the
  summary takes the total duration from every run and the split and the query count only from the runs that have events. The cold-cache trace of
  `tools/trace_query.ps1` clears the cache through the engine and is the better witness of a cold run; it is one run, not
  a median, and a traced run is slower than a benchmarked one (the trace adds work).

## The timings, before and after

Milliseconds, medians over five runs with the minimum and maximum in brackets, from the summary files above, first pass
(plain forms first). Storage-engine queries are the median over the runs that have events. **Tested**.

| Query | Cells | Cold, plain | Cold, rewrite | Warm, plain | Warm, rewrite | Storage-engine queries, plain to rewrite |
|---|---:|---|---|---|---|---:|
| `as_at_release_by_year` (release x year) | 151 | 13 (11-17) | 14 (13-17) | 5 (4-7) | 8 (7-8) | 4 to 4 |
| `as_at_release_by_department` (release x department) | 1,931 | 31 (28-32) | 33 (32-37) | 27 (23-30) | 27 (24-35) | 4 to 4 |
| `as_at_release_year_department` (stress shape, not a page) | 9,065 | 133 (131-140) | 157 (147-160) | 130 (123-135) | 137 (130-148) | 4 to 4 |
| `rank_ytd_variance_one_year_month` (2024-25, period 12) | 23 | 259 (237-267) | **154 (150-162)** | 237 (230-244) | **153 (147-157)** | 85 to 49 |
| `rank_ytd_variance_three_years` | 69 | 203 (196-213) | **111 (107-113)** | 147 (140-150) | **80 (74-85)** | 43 to 23 |

Second pass, rewrites first, same commands with `-OutDir evidence/perf/second_pass/<rewrite|naive>`:

| Query | Cold, plain | Cold, rewrite | Warm, plain | Warm, rewrite |
|---|---|---|---|---|
| `as_at_release_by_year` | 13 (11-17) | 13 (13-14) | 5 (5-7) | 7 (5-8) |
| `as_at_release_by_department` | 30 (30-37) | 33 (31-34) | 24 (22-32) | 27 (23-34) |
| `as_at_release_year_department` | 143 (140-147) | 138 (134-150) | 131 (130-140) | 127 (123-134) |
| `rank_ytd_variance_one_year_month` | 270 (260-281) | 160 (147-167) | 267 (253-274) | 157 (152-162) |
| `rank_ytd_variance_three_years` | 240 (230-390) | 111 (110-113) | 171 (163-257) | 77 (74-83) |

Reading it, honestly:

- **The rank is faster in both passes and in both cache states, with no overlap between the plain and rewritten ranges.**
  Cold medians fall by 41% (259 to 154) and 45% (203 to 111) in the first pass, 41% and 54% in the second. The warm
  medians fall by a similar share, which is expected: the work is formula-engine work and storage-engine scans that
  differ per group, not a cold cache. (In the second pass a plain-form run of the three-year query had a 390 ms outlier;
  the median is what I quote.)
- **The as-at measure did not get faster, and I will not claim it did.** The cold median of the rewrite is higher than the
  plain form's on the two small shapes in the first pass (by 1 and 2 ms) and in the second on one of them (3 ms; the other is
  equal), all inside the range of the runs, and it is 24 ms higher on the stress grid in the first pass and 5 ms lower in the
  second. The rewrite is therefore not lower in the first, same-session pass, and in the reversed pass the two are the same
  within the spread. The acceptance condition "the rewrite's
  cold median is lower" holds for slow measure 2 and does **not** hold for slow measure 1.
- Before this run I tried two more forms of the as-at measure as `DEFINE MEASURE` overrides in a scratch session: a
  `REMOVEFILTERS` limited to the two label columns of `Release` (timed only; stress grid cold 148 ms against 147 for the plain
  form in that session) and a `WINDOW` from the first release to the current one over `ALL ( 'Release'[Release Sequence] )`
  (the same cells as the plain form by file comparison; stress grid cold 140 ms against 147). Neither was faster beyond the
  spread. The scratch files are not kept, so these two numbers have no result file behind them and I am not relying on them.

## What the traces show

One cold-cache run each, [naive](../evidence/perf/naive/traces/) and [rewrite](../evidence/perf/rewrite/traces/). **Tested**.
The formula-engine figure is the total less the storage-engine time, so it is approximate (storage-engine scans can run in
parallel).

| Query | Total ms, plain / rewrite | Storage engine ms | Formula engine ms (derived) | Storage-engine queries (cache hits) | Storage-engine queries with a callback | Logical plan lines |
|---|---|---|---|---|---|---|
| `as_at_release_by_year` | 65 / 67 | 7 / 9 | 58 / 58 | 4 (0) / 4 (0) | 0 / 0 | 19 / 19 |
| `as_at_release_by_department` | 126 / 117 | 4 / 8 | 122 / 109 | 4 (0) / 4 (0) | 0 / 0 | 19 / 19 |
| `as_at_release_year_department` | 269 / 266 | 14 / 13 | 255 / 253 | 4 (0) / 4 (0) | 0 / 0 | 21 / 21 |
| `rank_ytd_variance_one_year_month` | 395 / 301 | 134 / 81 | 261 / 220 | 85 (19) / 49 (9) | 64 / 36 | 1,918 / 1,166 |
| `rank_ytd_variance_three_years` | 371 / 221 | 76 / 40 | 295 / 181 | 43 (18) / 23 (5) | 0 / 0 | 1,541 / 787 |

(The physical plan of both rank queries is cut at 10,001 lines by the trace in both forms, so its length is not compared.)

**Why the as-at measure did not change.** In both forms the plan is the same shape: four storage-engine queries whatever the
number of cells, one scan of `Fact Outturn` grouped by release, financial year and department with the 31 release sequences in
the filter, then a formula-engine step that builds the list of (release, release up to it) pairs once (496 rows, in an
`AggregationSpool`) and looks every cell's earlier releases up in it (`Spool_MultiValuedHashLookup`, `CrossApply`). The
`FILTER ( ALL ( 'Release' ) )` of the plain form is not evaluated per cell; the engine builds it once. The rewrite's
first 40 lines of the logical and of the physical plan of the two forms are the same operator for operator and record count for
record count (compare the two compact trace files of any of the three queries); only the internal column numbers differ
(`Release Sequence` is column 7 in one and 3 in the other), so the engine reads the two forms as the same computation. The time is the lookups: the stress grid has 9,065 cells that each add up to 31 releases of an
already-fetched result (about 130 ms, almost all formula engine) and the storage engine is 14 ms of it. A column filter versus
a table filter cannot change that. The plain `Outturn` over the same columns has only 1,842 non-blank cells (a delta exists only
in the release that made it) and takes 28 ms cold
([evidence/perf/baseline/summary.csv](../evidence/perf/baseline/summary.csv), queries in `tests/perf/baseline/`; not a
like-for-like comparison). The as-at grid has about five times as many cells because every figure is carried forward to each
later release, which is the content of the measure and not a form of writing it. What would remove the cost is a
precomputed as-at layer in the model, which would change the model and its size, and I have not built it. This agrees with
the earlier prediction in this page ("has little to gain on a page"). **Designed, not run**: the cost matters if the
measure is placed under a calculation item that evaluates it several times; I have not timed that.

**Why the rank got faster.** The plain form evaluates the Variance % and YTD calculation three times per cell: once for the
guard, once for each group in the table filter of `RANKX`, once for each group as its value. Each evaluation resolves the
year-to-date window again (`Window.Ytd`, with `LatestPeriod` and `Years` passed as callbacks to the storage engine). The
rewrite evaluates it once for the guard and once per group, in `ADDCOLUMNS`, and `RANKX` ranks a stored column. The
trace shows the effect: storage-engine queries 85 to 49 and 43 to 23 (-42% and -47%), storage-engine queries that carry a
callback 64 to 36, the most repeated storage-engine query 14 times to 8 (the scan that resolves the window) and 8 to 4 (a scan of
`Fiscal Year`), distinct query texts 64 to 44 and 50 to 36, and a logical plan 39% and 49% shorter. Storage-engine time falls by
40% and 47% (134 to 81 ms, 76 to 40 ms) and formula-engine time by 16% and 39% (261 to 220, 295 to 181). The remaining cost is one
resolution of the window for each of the groups in each cell, which the form does not remove: a rank of N groups
evaluates N windows per cell, and the matrix of three years evaluates it for 69 cells. I did not find a form that avoids that
without precomputing the window, and I tried a `RANK` with `ORDERBY` over the same `ADDCOLUMNS` table in a scratch session: the two
queries returned identical files and ran in about the same time (cold 143 against 139 ms for one year, 107 against 104 ms for
three), so I kept `RANKX`. Those scratch files are not kept either.

## VertiPaq: one change tried, none kept

`tools/run_dax.ps1 -Vpax` and `tools/vpax_summary.py` (the raw `.vpax` is not kept):
[evidence/perf/rewrite/model_size/](../evidence/perf/rewrite/model_size/) (tables.csv, columns.csv), taken after the
timings of this session. The reported total is 141.7 MB across 31 tables, which is not the size of the content: every text
column, even of a four-row table, reports a dictionary of about 1 MB, an allocation the engine makes when a text column is
loaded (the earlier project's notes saw the same). `Fact Outturn` reports 6.4 MB, of which the amount column
(`Amount Delta`, `Decimal`, hash encoded, 84,291 distinct values) is 4.5 MB: a 2.8 MB dictionary and 1.7 MB of data. Nothing else
in the model is both large and real content: the next largest columns are text columns of 1.0 to 1.2 MB each, which are the
allocation above.

The one change I tried was `encodingHint: value` on `Amount Delta`, to see whether value encoding would store the amount
without a dictionary. Desktop took the property (read back through TOM as `Value`), the model was reloaded and refreshed, the
queries were run and the export taken again: the column is still `HASH` with the same dictionary and data sizes, and the
whole table list is byte for byte the same
([evidence/perf/rewrite/model_size_value_hint/](../evidence/perf/rewrite/model_size_value_hint/)). The engine ignored the
hint for this column (I did not find out why; the range of the stored amounts is a candidate I did not test: the NHS Pension Scheme
unit error is 4,100,000,000 in GBP thousands, which is about 4.1e13 once stored with four decimals). I reverted it, so the model carries no change for VertiPaq and the size before and after is the
same 4,533,620 bytes for the column and 141,747,522 for the model. **Tested**.

I did not drop a column. The visible text columns of the large tables (the three sub-segment labels, organisation and
economic-category codes) are attributes a report uses, and dropping one would save a 1 MB allocation and not content. A
smaller amount column would need a smaller data type or less precision, and the amounts have to tie to the source to four
decimals.

One difference to note. The first baseline of this page (`evidence/perf/naive/model_size/`, taken in an earlier session)
reports the amount column at 5.2 MB, with a 674,336-byte hierarchies figure that this session's export does not have. I did not find the cause: a
hierarchy that is built on demand by the queries run before the export would explain it, but I did not test that. Compare model
sizes only between exports taken after the same queries.

## Slow measure 3: the allocated amount through the weighted bridge

`Allocated Amount` spreads the Cabinet Office administration pool over the departments through `Allocation Bridge (derived)` ([model.md](model.md#the-allocation-of-a-shared-cost-pool-and-the-what-if)).
The plain form is kept hidden as `Allocated Amount (naive)`, display folder `Performance\Naive`: a `SUMX` over each department and pool of the bridge, with a
`CALCULATE` for the pool and another for the weight of each pair. The rewrite adds the stored allocated amount, one pass over the bridge.
Queries: `tests/perf/allocation_*.dax` (rewrite) and `tests/perf/naive/allocation_*.dax` (plain), the same text on the two measures.

**The bridge is small (108 rows), so every figure below is a few milliseconds and the page does not need the rewrite.** I wrote the measure the plain
way first, as the task asked, and timed both; I report the numbers and do not call a 4 ms difference a win.

**Same results, within a stated rounding.** **Tested**: tests 952 and 953 return both forms side by side with their difference, each compared with
its own SQL recomputation (`ukfr dax-compare`: 128 of 128 pass; largest absolute difference 0 for both). The two forms are not equal by design: the plain form
is the pool times the stored weight with each product held to four decimals (the engine rounds a product with a fixed-decimal amount), the rewrite is
the stored amount that carries the rounding remainder. They differ by up to 0.0004 in GBP thousands (GBP 0.40) in a year and by at most 0.000048 in a cell
(test 952: 108 cells; test 953: 8 years). I first expected the totals to be equal and test 953 failed on the 4-decimal rounding, so the expected values now
carry it.

Milliseconds, medians of five runs with the minimum and maximum in brackets, from `evidence/perf/{naive,rewrite}/summary.csv` (first pass, plain forms first)
and `evidence/perf/second_pass/{rewrite,naive}/summary.csv` (rewrites first). **Tested**.

| Query | Cells | Cold, plain | Cold, rewrite | Warm, plain | Warm, rewrite | Storage-engine queries, plain to rewrite |
|---|---:|---|---|---|---|---:|
| `allocation_by_year` | 8 | 10 (8-10) | 4 (3-7) | 7 (5-7) | 3 (2-5) | 5 to 1 |
| `allocation_by_department` | 21 | 7 (6-8) | 4 (3-4) | 6 (5-7) | 3 (3-4) | 4 to 1 |
| `allocation_by_department_year` | 108 | 10 (10-13) | 6 (4-7) | 7 (6-11) | 5 (4-5) | 6 to 1 |

Second pass, rewrites first:

| Query | Cold, plain | Cold, rewrite | Warm, plain | Warm, rewrite |
|---|---|---|---|---|
| `allocation_by_year` | 10 (9-10) | 3 (3-7) | 7 (5-9) | 4 (3-5) |
| `allocation_by_department` | 10 (7-10) | 3 (3-4) | 7 (5-8) | 3 (3-5) |
| `allocation_by_department_year` | 10 (8-11) | 7 (4-7) | 8 (7-10) | 5 (3-7) |

**The rewrite has the lower median in all 12 cells and in both orders, by 2 to 7 ms. In the cold cells the ranges do not overlap; in four warm cells they touch (5 ms, or 7 ms for the widest grid of the second pass).**
With so few milliseconds that is a statement about rank on this machine, not about scale: the plain form's cost grows with the number of bridge
rows, which I did not test beyond 108.

Traces (one cold run each, [naive](../evidence/perf/naive/traces/), [rewrite](../evidence/perf/rewrite/traces/); a traced run is slower than a benchmarked one). **Tested**.

| Query | Total ms, plain / rewrite | Storage-engine queries | Distinct storage-engine texts | Logical plan lines |
|---|---|---|---|---|
| `allocation_by_year` | 91 / 83 | 5 / 1 | 10 / 2 | 22 / 7 |
| `allocation_by_department` | 82 / 82 | 4 / 1 | 8 / 2 | 22 / 7 |
| `allocation_by_department_year` | 86 / 83 | 6 / 1 | 12 / 2 | 24 / 9 |

The traced totals are within 8 ms and mostly formula-engine time of a cold start (the storage engine takes 0 to 4 ms in both forms), so the trace does not
separate the forms by time. It separates them by work: the plain form asks the storage engine for the pool and for the weight of each pair, the rewrite
for one scan of the bridge, and its plan is about a third as long.

## Not run

- Slow measure 3 at scale: the bridge has 108 rows; I did not time a larger bridge, so how the plain form grows is not tested.
- No query was timed under the calculation groups' items on the restatement measures other than in the correctness tests
  (`tests/dax/769_restatement_under_time_and_unit.dax`, which is not a benchmark).
- No report page timing: no Performance Analyzer capture of a visual; the queries stand in for visuals. The rank queries carry the plan
  measure filter of the page, but the page itself was not timed.
- Cold runs through `dscmd` are not trustworthy to the last run (above); the traces cover the cold case once each.
- Ties in the rank (above), and the as-at measure under Time Intelligence items.
- Nothing in the Power BI service.
