# 0006. Compare a plan only at the grain it is published at, and enforce it in the model

## Status

Accepted

## Context

A plan is not published at the grain outturn is. Four sources give four grains:

| Grain | Source | Published by |
|---|---|---|
| A | OSCAR Plans, FY2017-18 to FY2021-22 | organisation, control budget detail, economic budget, year |
| B | Estimates, FY2023-24 to FY2026-27 | Spending Review group, resource DEL excluding depreciation or capital DEL, year |
| C | Estimates, FY2022-23 | the same, with BEIS, DCMS and DIT as one group |
| D | PESA departmental AME and administration | group, measure, year |

Outturn is held by month, organisation, sub-segment and economic category. A variance at any grain finer than the plan's
is a comparison of a published number with an allocation, and it looks precise. The profile of the OSCAR Plans measured
the effect: the sum of absolute variances over outturn is 5 to 11% at organisation x control budget x economic budget,
the real underspend, and jumps to 19 to 38% one step finer, at economic group, where most of it is allocation noise.

## Decision

- OSCAR Plans are compared with outturn at year x organisation x control budget detail x economic budget, and no finer.
  Plans from FY2023-24 are compared at Spending Review group x resource DEL excluding depreciation, and capital DEL.
- The rule is written once, as the model function `Grain.BelowGrain`, and `Plan` returns BLANK whenever the filter context
  is finer than the plan's grain: a month, a quarter or a window, a sub-segment, a department, an economic category, an
  organisation version. It never repeats a coarse plan against a finer selection.
- `Plan (phased)` is the one plan measure that may go to a month. It is my allocation of the annual plan (shares from the
  previous year's outturn), it is flagged derived in the table, the measure and the page titles, and nothing adds it to
  `Plan` or `Outturn`.
- The report compares plan and outturn by Spending Review group, not by department.

## Consequences

- There is no plan variance by department. I had planned department as the breakdown of the variance page and a monthly
  phased plan on the department page; both changed, and the pages say why ([pages.md](../pages.md)).
- A plan figure can be BLANK, and that is correct, not a missing value. A reader sees a plan badge beside each plan figure
  that names the source and the grain for the year in view.
- Row-level security meets the same grain: a user sees the plan of a group only when every department of the group is the
  user's, because a part of a group has no plan ([security.md](../security.md#the-plan-under-row-level-security-my-decision)).
- A selection of every member does not count as a selection (the guard compares row counts), so a slicer left on "select
  all" does not blank the plan. That is by construction and no test selects every member (**designed**).
- A cost I have not reduced: the guard costs about a dozen row counts per call, and a matrix of comparison items pays it per
  cell ([model.md](../model.md#query-timings)).

## Evidence

- The grain profile (table of grains and variance noise): [profiling/oscar-annual-extracts.md](../profiling/oscar-annual-extracts.md).
- The four grains in the fact and the controls: [data-dictionary/plans.md](../data-dictionary/plans.md), `sql/tests/508_fact_plan_grain.sql`.
- The guard and the table of what blanks the plan: [model.md](../model.md#the-plan-grain-guard).
- **Tested**: `Plan` is BLANK at a month, a sub-segment, an economic category, an organisation version, a department and a
  data-quality issue, and is the number of keys the plan has at its own grain
  ([tests/results/723_plan_grain_guard.csv](../../tests/results/723_plan_grain_guard.csv)); all 881 cells of `Plan` by
  organisation code, control budget detail and economic budget for 2019-20 equal the plan fact
  ([tests/results/734_plan_grain_a_by_organisation.csv](../../tests/results/734_plan_grain_a_by_organisation.csv)). Both
  tests are in [evidence/model/dax_tests.csv](../../evidence/model/dax_tests.csv).
