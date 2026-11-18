# Performance: the plain forms of the slow measures

This page holds the first performance evidence for the semantic model: two measures written in the plain form a report
author would write, timed and traced as they are. Nothing here is a rewrite and nothing has been optimised; a later
piece of work rewrites them and compares against these files. Every claim is labelled **tested** (with the command and the
result file) or **designed**. The timings rank queries against each other on one machine; they are not absolute figures
and say nothing about the Power BI service, which I do not use.

## What is measured

| Measure | Where | What makes it a candidate for a rewrite |
|---|---|---|
| `Outturn as at Release` (slow measure 1) | `Fact Outturn`, folder Restatement | the sum of the revision deltas of every release up to the highest in context, written as `CALCULATE ( [Outturn], FILTER ( ALL ( 'Release' ), 'Release'[Release Sequence] <= AsAt ) )` |
| `Department Group Rank (YTD Variance %)` (slow measure 2) | `Fact Outturn`, folder Plan\Ranking | `RANKX` over the Spending Review groups of a `CALCULATE` that applies the Variance % item of Scenario Comparison and the YTD item of Time Intelligence, written three times (the guard, the table filter and the value) |
| weighted allocation through the allocation bridge (slow measure 3) | **pending** | it depends on the allocation bridge of a later phase. There is no measure and no number yet; this line is the placeholder |

The second measure ranks Spending Review groups and not departments of the current structure, because the plan is
published by group and `Plan` is BLANK for a selection of a department (the grain guard): a rank of the year-to-date
variance % over departments would be BLANK everywhere. The year-to-date variance % exists only at period 12 or for a whole
year, because a year-to-date window before the year end is never a published plan period (`docs/model.md`, Time
Intelligence); so the rank query holds period 12 or a whole year.

## Setup, and how the files were made

- Power BI Desktop, Microsoft Store build 2.159.1231.0, the model `model/UKGroupFinance.pbip` open in it, Import mode,
  compatibility level 1702, data from the full-scope warehouse (`Fact Outturn` 658,554 rows). Nothing else was queried
  during a run.
- Model size, from `tools/run_dax.ps1 -Vpax` and `tools/vpax_summary.py` (the raw `.vpax` is not kept):
  [evidence/perf/naive/model_size/tables.csv](../evidence/perf/naive/model_size/tables.csv) and
  [columns.csv](../evidence/perf/naive/model_size/columns.csv). The reported total is 113.8 MB across 25 tables, which is
  not the size of the content: every text column of even a four-row table reports a dictionary of about 1 MB, an
  allocation the engine makes when a text column is loaded (the earlier project's performance notes saw the same). The
  fact table reports 7.1 MB, of which the amount column is 5.2 MB (84,291 distinct values). **Tested** (this command, these
  files).
- Queries: `tests/perf/*.dax`, one file per query, each shaped like the visual that would use it.
- Timings: `powershell.exe -NoProfile -File tools/run_dax.ps1 -QueryDir tests/perf -OutDir evidence/perf/naive -Benchmark -Cold 5 -Warm 5`
  (`dscmd benchmark`: five runs with the cache cleared, then five warm). One CSV per query holds every run
  ([evidence/perf/naive/](../evidence/perf/naive/)). `python tools/summarise_benchmarks.py` reads them and writes
  [summary.csv](../evidence/perf/naive/summary.csv) (median, minimum and maximum of the total duration for each query and
  cache state).
- Traces: `powershell.exe -NoProfile -File tools/trace_query.ps1 -QueryFile tests/perf/<name>.dax -Cold` once per query,
  then `python tools/compact_traces.py <folder of full traces> evidence/perf/naive/traces`. The full traces run to
  megabytes (every storage-engine query and the whole physical plan), so what is committed is the compact form: the
  counts and times, the ten longest storage-engine queries with their text, the most repeated one, and the first 40 lines
  of the logical and physical plans with the length of the whole plan
  ([evidence/perf/naive/traces/](../evidence/perf/naive/traces/)). The script removes drive paths and this machine's name
  and account and stops if one is left.

Two things about the tool to keep in mind. Some of its runs lose the trace events: one of the five cold runs of
`as_at_release_by_department` reports zero storage-engine queries although the cache was cleared, and the same happens to
warm runs of four of the five queries (see `runs_with_events` in the summary). The summary therefore takes the total duration from every run and the
split and the query count only from the runs that have events, and says how many those are (`runs_with_events`). The
cold-cache trace of `tools/trace_query.ps1` clears the cache through the engine and is the better witness of a cold run;
it is one run, not a median.

## The timings

All from [summary.csv](../evidence/perf/naive/summary.csv), milliseconds, medians over five runs with the minimum and
maximum in brackets; the storage-engine query count is the median over the runs that have events. **Tested**.

| Query (`tests/perf/`) | Shape | Rows | Cold median (min-max) | Warm median (min-max) | Storage-engine queries |
|---|---|---:|---:|---:|---:|
| `as_at_release_by_year` | release x financial year, 31 x 9 | 151 | 12 (10-17) | 4 (4-7) | 4 |
| `as_at_release_by_department` | release x department of the current structure | 1,931 | 30 (27-36) | 17 (17-28) | 4 |
| `as_at_release_year_department` | release x year x department (a stress shape, not a page) | 9,065 | 140 (137-151) | 136 (130-137) | 4 |
| `rank_ytd_variance_one_year_month` | rank of the Spending Review groups, 2024-25, period 12 | 23 | 293 (278-303) | 274 (267-290) | 129 |
| `rank_ytd_variance_three_years` | the same rank for three years | 69 | 241 (240-247) | 163 (158-187) | 63 |

What the cold-cache traces say (one run each; **tested**, [evidence/perf/naive/traces/](../evidence/perf/naive/traces/)):

| Query | Total ms | Storage engine ms | Formula engine ms (derived) | Storage-engine queries (cache hits) | Longest plan |
|---|---:|---:|---:|---:|---|
| `as_at_release_by_year` | 44 | 7 | 37 | 4 (0) | 19 logical lines |
| `as_at_release_by_department` | 77 | 6 | 71 | 4 (0) | 19 |
| `as_at_release_year_department` | 243 | 16 | 227 | 4 (0) | 21 |
| `rank_ytd_variance_one_year_month` | 373 | 190 | 183 | 129 (26) | 1,946 logical lines; the physical plan is cut at 10,001 lines by the trace |
| `rank_ytd_variance_three_years` | 376 | 90 | 286 | 63 (23) | 1,563 logical lines; cut at 10,001 |

The formula-engine figure is the total less the storage-engine time, so it is approximate: storage-engine scans can run in
parallel.

## What the traces show

**`Outturn as at Release` is not slow at this data size.** In its plain form it is four storage-engine queries whatever
the number of cells: the engine scans `Fact Outturn` once, grouped by financial year and release sequence, with the 31
release sequences in the filter, and adds up the running sum in the formula engine. The time grows with the number of cells
and almost all of it is formula engine: 151 cells take 12 ms cold, 1,931 take 30 ms and 9,065 take 140 ms, and the
storage engine is 6 to 16 ms of the traced runs. A rewrite (a running sum by `WINDOW`, or a cumulative column) can save
tens of milliseconds on a matrix of a few thousand cells and has little to gain on a page; I would not claim more than
that before it is measured against these files. The measure's cost will matter if it is placed under a calculation group
item that evaluates it several times (a year-to-date or previous-year item of it), which I have not timed.

**The rank is the heavier shape.** `Department Group Rank (YTD Variance %)` takes 160 to 290 ms for 23 to 69 cells and
129 storage-engine queries for the 23 groups of one year. In the one-year trace the most repeated storage-engine query (24 times) and six of the ten longest are the one that
resolves the year-to-date window: the filter over `Fiscal Period` that `Window.Ytd` builds, with `LatestPeriod` and
`Years` passed to it as callbacks. In the three-year trace none of the ten longest is that query and the most repeated is a
scan of `Fiscal Year` (16 times), so the cost is spread over many small scans (63 storage-engine queries, none of the
ten longest above 11 ms) and the formula engine is the larger share of the time. The plain form evaluates the
YTD and Variance % calculation once for the guard on the row, once for each row in the table filter of `RANKX` and once for
each row as its value, and each evaluation resolves the window again. Computing the group's value once into a table
(`ADDCOLUMNS` over the groups) and ranking that is the obvious rewrite, and it should remove most of those queries; that is
a prediction, not a result.

## Not run

- Slow measure 3: pending the allocation bridge (above). No measure, no query, no number.
- No query was timed under the calculation groups' items on the restatement measures other than in the correctness tests
  (`tests/dax/769_restatement_under_time_and_unit.dax`, which is not a benchmark).
- No report page exists, so no Performance Analyzer capture of a visual; the five queries stand in for visuals.
- Cold runs through `dscmd` are not trustworthy to the last run (above); the traces cover the cold case once each.
- Nothing in the Power BI service.
