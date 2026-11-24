# 0004. Store revision deltas, not stacked snapshots

## Status

Accepted

## Context

Each OSCAR in-year release is a snapshot of one financial year to date, and a later release restates months that an
earlier one already reported. A reader of a finance report needs the latest figure, what a given release stated, and how
much changed between releases. There are 31 releases, March 2019 to September 2026.

There are two ways to hold that: stack every release as it was published (every line of every release), or store, for
each line, only what each release changed compared with the previous release of the same financial year.

## Decision

`dw.fact_outturn` holds revision deltas. For a release R and a line (organisation, sub-segment, economic category, control
budget detail, month), the delta is the amount in R less the amount in the previous release of the same financial year,
and only non-zero deltas are stored. A line that was reported and then dropped gets a negative delta that reverses it.
"As at release R" is the sum of the deltas up to R for R's financial year, and it equals what R reported.
`revision_no` is 0 on the first delta of a line, so "as first reported" is `revision_no = 0`.

Zero-amount rows are dropped before the deltas are computed (ten releases are zero-filled grids). Deltas are computed on
the warehouse keys of the organisation version each release used, so a body that changes version inside a year reverses
under the old key and appears under the new one, and the as-at amount still equals the release.

## Consequences

- The fact is smaller than the stack. The 31 files hold 1,547,078 rows, of which 218,092 are zeros, so stacking the
  non-zero rows would give 1,328,986. The profile found 649,475 non-zero deltas, and the fact has 658,554 rows. Every
  one of the 9,079 extra rows is accounted for: +10,749 where a key changes inside a year, -1,652 deltas below 0.0001
  and -18 sub-segment codes that differ only in case.
- A plain sum of the fact with nothing selected on `Release` is the latest view of every year. With one release selected it
  is that release's delta, not the figure at that release. The figure at a release therefore has its own measure
  (`Outturn as at Release`), and the sum of one release's deltas is called `Revision in Release` so that nobody
  mistakes it for a total.
- "As at" costs formula-engine time, because each cell adds up to 31 releases of an already fetched result. I tried three
  forms of the measure and none was faster than the plain one (see [performance.md](../performance.md)). A precomputed
  as-at layer would remove the cost, and I have not built it.
- A source error shows in the deltas as well as in the stack. One NHS Pension Scheme line was reported 1,000 times too
  large in a release and corrected in the next, so its restatement is enormous. `dw.dq_issue` flags thirteen fact rows
  and the restatement measures have an `(excl. flagged)` variant, so the error is shown and not hidden.
- The 71 rows that June 2019 labels period 0 stay as period 0 of FY2018-19 and count in year totals; they are not
  dropped.

## Evidence

- Counts and the build of the fact: [data-dictionary/outturn.md](../data-dictionary/outturn.md). The 649,475 and
  1,547,078 are in the "Decisions this supports" list of [profiling/oscar-inyear.md](../profiling/oscar-inyear.md).
- The explanation of 658,554 against 649,475:
  `sql/tests/313_row_counts_agree_with_the_profile_and_every_difference_is_explained.sql`.
- **Tested**: the sum of the deltas up to each release equals that release's control total, difference exactly 0, in
  31 of 31 releases ([evidence/build/delta_invariant.csv](../../evidence/build/delta_invariant.csv), `sql/tests/300`,
  `301` and `302`). The model's `Outturn as at Release` equals the file total of every release
  ([tests/results/760_as_at_release_equals_file_total.csv](../../tests/results/760_as_at_release_equals_file_total.csv);
  test 760 in [evidence/model/dax_tests.csv](../../evidence/model/dax_tests.csv)).
- The pinned row count and sum of the real fact:
  [evidence/expected/real_fact_totals.csv](../../evidence/expected/real_fact_totals.csv),
  `pipeline/tests/test_real_totals.py`.
- How the restatement measures are defined and tested:
  [model.md](../model.md#restatement-how-a-figure-changed-from-release-to-release).
