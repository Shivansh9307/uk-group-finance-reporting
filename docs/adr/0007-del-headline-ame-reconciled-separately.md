# 0007. The headline plan variance is DEL only, and AME is reconciled separately

## Status

Accepted

## Context

My first version of the executive page led with a plan variance of -8.5% in 2025-26 (-110.24bn), from all four plan
measures: resource DEL excluding depreciation, capital DEL, departmental resource AME and departmental capital AME. That was
a mismatch of bases, not an underspend.

- DEL is a limit that Parliament votes. Its plan and its outturn are on the same footing.
- Departmental AME is a forecast (a PESA figure), and the in-year outturn of AME is a first look that lacks the year-end
  provisions, impairments and pension entries that the restated annual file carries. In 2024-25 resource AME is 471.2bn
  in-year, 495.8bn in the annual file and 494.6bn in PESA December 2025.
- PESA 2026 puts about 20, 40 and 45bn a year of ringfenced depreciation in resource AME that the earlier PESA has in
  resource DEL, so its AME outturn is not on the framework of the plans.

I found this by building an audit that sets the outturn on the plan's basis beside the plan, for every year and Spending
Review group from FY2022-23, and measures both against an independent outturn (the restated annual file, and the Public
Spending Statistics for DEL in 2025-26). That is 364 cells.

## Decision

- The headline plan variance is resource DEL excluding depreciation plus capital DEL. A report-level filter on
  `Fact Plan[Plan Measure]` keeps those two measures on the Executive summary, Variance and Group detail pages.
- AME is not hidden. It is reconciled in its own table, `Plan Variance Check` (from `audit.plan_variance_reconciliation`),
  with one verdict per cell: `ok`, `fixed`, `explained` or `unexplained`, and the reason.
- The P&L statement page no longer shows plan columns, because its total line would add DEL limits to an AME forecast.
- Outturn on the plan's basis (`Outturn (plan basis)`) is a model measure with ten explicit rules, one per plan measure,
  so the comparison is like for like.

## Consequences

- The DEL variance in 2025-26 is -8.50bn on a plan of 645.98bn, -1.3%. The AME gap, 101.7 to 125.2bn a year, is shown on the
  Variance page as reconciled and is not called a variance.
- Of the 364 cells, 233 are `ok`, 4 `fixed`, 120 `explained` and 7 `unexplained`. The seven are each under 1bn and none is a
  headline item; I list them in [reconciliation.md](../reconciliation.md#9-plan-variance-reconciliation-full-scope) and I do
  not know their cause.
- The audit found two real defects, which I fixed: FY2022-23 had a plan for BEIS, DCMS and DIT as one group and an outturn
  on the new structure (a plan with no outturn), and departmental AME was missing from the annual basis table.
- The filter is on the report, not in the model. A user who builds a visual on the model without it sees all four plan
  measures together. I chose the report filter because every plan measure stays available and tested; the cost is that
  the model does not enforce the headline by itself.
- The 2025-26 AME cells and the Home Office 2025-26 cell are explained by a carry-forward from 2024-25, not measured, because
  no annual file for 2025-26 exists yet.
- The audit needs the full-scope database (the restated annual files are not in git). CI does not rerun it; its result
  file and the tests that pin it are committed.

## Evidence

- The chain, the verdict counts, the fixes and the residuals:
  [reconciliation.md](../reconciliation.md#9-plan-variance-reconciliation-full-scope),
  [evidence/full/plan_variance_reconciliation.csv](../../evidence/full/plan_variance_reconciliation.csv),
  [evidence/full/pesa_2026_basis_change.csv](../../evidence/full/pesa_2026_basis_change.csv).
- **Tested** (full scope): `sql/tests/800` to `804` (the regrouped FY2022-23 outturn, AME on the annual basis table, the
  reconciliation adds up and pins its seven unexplained cells, the PESA 2026 basis change, and the model's view keeps every
  row and amount).
- **Tested**: the headline figures and the before-and-after by year are DAX tests 788 and 801
  ([tests/results/788_exec_headline_figures.csv](../../tests/results/788_exec_headline_figures.csv),
  [tests/results/801_plan_variance_by_year_and_measure.csv](../../tests/results/801_plan_variance_by_year_and_measure.csv)),
  and the figures read off the screenshot equal them
  ([evidence/report/screenshot_figures.csv](../../evidence/report/screenshot_figures.csv)).
- The report filter and the pages: [pages.md](../pages.md#the-pages), `tools/build_report.sh` (function `report_filters`).
