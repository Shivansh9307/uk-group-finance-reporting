# Data dictionary: plans and outturn on one basis

What `ukfr build` adds so that a plan and the outturn it is compared with are on the same footing: a bridge
from outturn lines to Spending Review groups, a monthly phasing of the annual plans, and outturn on the
plan's measures. Amounts are GBP thousands, spending positive, income negative, `DECIMAL(19,4)`; shares are
`DECIMAL(19,10)`. Every claim is labelled **tested** (the test or command) or **designed** (not run).

Real and derived stay apart. The bridge and the plan-basis outturn tables regroup real outturn. The phasing
profile and the phased plan are **derived**: the monthly plan figures are not published, they are my
allocation of a published annual figure. They are flagged `is_derived = 1`, their table descriptions start
with DERIVED, and no real total reads them (see "Nothing derived reaches a real total").

## Register of authored data

| Object | What it is | Why | Where it can reach |
|---|---|---|---|
| `authored/department_sr_group.csv` (`authored.department_sr_group`, `stg.department_sr_group`) | 63 rows. 59 give a current department number its Spending Review group; one is an organisation exception (department 085, durable key `LGV`, to CLG Local Government); three name the departments of the combined pre-2023 group (013, 048, 084, basis `pre2023_as_reported`). Each row has evidence and a note | no source says which Spending Review group a department number belongs to for the whole of the outturn. The latest annual release (BUD_24-25.xlsx, November 2025) says it for the organisations it covers, and I copied that. Departments that no longer exist (011, 027, 035, 077) have no row: the current-structure map sends their lines to a department that exists or to an Unallocated member | `dw.outturn_sr_group_bridge` (which group an outturn line is added to) and the combined-group phasing profile. It holds no amount. **Tested**: `sql/stg/550_department_sr_group.sql` stops the build on an unknown basis, a missing evidence or note, a group that is not a member of `dw.dim_sr_group`, an exception without a department row, and `sql/tests/551` pins the result against the file |

## Tables

| Table | Rows, committed scope | Rows, full scope | Grain |
|---|---|---|---|
| `stg.department_sr_group` | 63 | 63 | typed copy of the authored file |
| `dw.outturn_sr_group_bridge` | 5,480 | 5,480 | organisation version x sub-segment |
| `dw.plan_measure_selection` | 10 | 10 | measure x control budget detail (a definition, not data) |
| `dw.outturn_plan_line` | 101,675 | 101,675 | release x period x organisation x control budget detail x economic budget x depreciation flag |
| `dw.plan_phasing_profile` | 8,988 (749 profiles) | 53,688 (4,474 profiles) | profile x period 1 to 12 |
| `dw.fact_plan_phased` | 8,988 | 53,688 | plan row x period 1 to 12 |
| `dw.outturn_plan_basis_inyear` | 34,048 | 34,048 | release x period x Spending Review group x measure |
| `dw.outturn_plan_basis_annual` | not built | 1,020 | vintage x financial year x Spending Review group x measure |
| `audit.sr_group_bridge_summary` | 24 | 24 | one row per group the bridge uses |
| `audit.plan_phasing_summary` | 17 | 27 | plan year x method |
| `audit.sr_group_bridge_vs_bud` | not built | 327 | organisation code x bridge group (`evidence/full/`) |
| `audit.plan_basis_inyear_vs_annual` | not built | 562 | financial year x group x measure (`evidence/full/`) |

Counts are from `evidence/build/table_counts.csv` (committed scope) and a full-scope build written to a
scratch directory.

## 1. The bridge: `dw.outturn_sr_group_bridge`

Each (organisation version, sub-segment) pair of the outturn, the same pairs as `stg.current_structure_map`,
gets exactly one `sr_group_key`. **Tested**: `sql/tests/550_every_outturn_line_has_exactly_one_sr_group.sql`
(every pair of `dw.fact_outturn` has one bridge row, no pair is bridged through an unknown department, and
the regrouped lines add up to `dw.fact_outturn`, in total and in every release).

The group follows the line's **current** department, because the Spending Review groups are the current
structure. The bridge reads `stg.current_structure_map.current_department_key`; it does not copy the rule
that fills it. The department number then picks the group from `authored/department_sr_group.csv`:

| `bridge_rule` | Pairs | Meaning |
|---|---:|---|
| `organisation exception` | 205 | the organisation has its own row for the department number: department 085 feeds CLG Communities and CLG Local Government, and I split it by organisation (durable key `LGV`), never by weight |
| `department` | 5,239 | the department number's own row |
| `unallocated member` | 36 (6 organisations) | the current department is an Unallocated member of `dim_department` (U084, U011, U077, U035: lines of a closed or split department with no current home, from `stg.current_structure_map`). They go to the outturn-only member `Unallocated: former department lines`, and are marked by this rule so that they can be left out; see below |
| `unknown department` | 0 | the structure map has no department; a test fails if any pair lands here |

A current department of type Department that has no row in the file stops the build with the list of numbers
(`sql/dw/550`). **Tested**: `sql/tests/551_bridge_follows_the_authored_department_rule.sql` recomputes the group
of every pair from the authored table, checks that every current row of the file is used, that department 085
is split into exactly two groups, that every pair whose current department is an Unallocated member is bridged
by the `unallocated member` rule to `Unallocated: former department lines` and no other pair is, and that no pair lands
in a plan-only, non-department or the combined pre-2023 member. `sql/tests/550` also fails if any line of
`dw.outturn_plan_line` is in `Unallocated central funds`.

**Unallocated lines.** The current-structure map sends the lines of a closed or split department that no
current department took over to an Unallocated member (BEIS shared lines, the Electoral Commission, the
Assets Recovery Agency, the Department for Exiting the European Union). The Spending Review groups have no
such member, so the bridge puts those 36 pairs in an outturn-only member of `dw.dim_sr_group`,
`Unallocated: former department lines` (`authored/sr_group.csv`, member type `outturn_only`), and every row
carries `bridge_rule = 'unallocated member'`. Each line has exactly one group; none is dropped.

I first put these lines in `Unallocated central funds`, the member where the plans put funds not yet allocated
to a department (Levelling Up Fund and similar). That overloaded one member with two unrelated meanings, and a
plan row of that member would have been phased on the outturn of closed departments. The new member has outturn
and no plan row; `Unallocated central funds` has plan rows (when a source publishes one) and no outturn line. A
plan row of `Unallocated central funds` therefore finds no outturn line in its profile and takes the existing
fallback, `flat_no_prior_year` (twelve flat twelfths). **Tested**: `sql/tests/506` (exactly one `outturn_only`
member, with outturn, not a department group, no plan row and no plan name mapped to it) and `sql/tests/550`
(no outturn line in a plan-side member, none in `Unallocated central funds`).

Effect on the phasing profile, measured on builds of `main` and of this change: **none**, because `dw.fact_plan`
holds no row for `Unallocated central funds` in either scope (the lines the name map sends there appear only in
PESA tables that the plan fact does not take). The method counts (committed scope: `prior_year_outturn` 553,
`flat_no_prior_year` 167, `flat_prior_not_positive` 29; full scope: 2,331, 1,808 and 335) are the same before and
after; `evidence/build/plan_phasing_summary.csv` is unchanged. The change is a correction of what the bridge
says, ahead of any plan row for that member, not of a number.

The combined pre-2023 group (BEIS, DCMS and DIT, which FY2022-23 plans are published as) is not a bridge
target: the outturn lines are on the current structure. It is used only for the phasing profile of a plan
row whose group is that member, through the three `pre2023_as_reported` rows.

### Bridge against the BUD (full scope)

`audit.sr_group_bridge_vs_bud` (`evidence/full/sr_group_bridge_vs_bud.csv`) sets the bridge group of every
organisation code against the group the newest annual release (vintage 2025-11) gives it in its newest
financial year; one row per organisation code and bridge group. **Tested** (`sql/tests/561`, full scope): of
the 283 organisation codes present in both, 255 agree on every pair and 28 (31 rows, 210 pairs) differ on
at least one, and the 31 rows are exactly the ones pinned in the test (BIS084 also has one agreeing row). The reasons:

| Organisations | Bridge group | BUD group | Why |
|---|---|---|---|
| 21 organisations with a code ending 084 (ACA, BBB, BPA, CIS, CSE, FFL, FRC, MEI, NPI to Business and Trade; CCC, CNC, COL, EHL, ESC, LCC, NDA, OGA, SAL, SCG, UKA, UKG to Energy Security and Net Zero) | Business and Trade or Energy Security and Net Zero | Science, Innovation and Technology | the BUD last lists them in FY2022-23 under the old BEIS group, which `BIS084.GROUP` maps to Science, Innovation and Technology; the bridge puts them where `stg.current_structure_map` says their lines went after the February 2023 reorganisation. This is the intended difference between the current structure and an annual file on the structure of its year |
| BIS084 (the BEIS core department) | Business and Trade (46 pairs), Energy Security and Net Zero (46), Education (1), Unallocated: former department lines (23); Science, Innovation and Technology (99 pairs) agrees | Science, Innovation and Technology | the BUD keeps the whole core department in one group; the current-structure map decides line by line which successor department each sub-segment went to. One organisation with five bridge rows is the intended result of a split, not an error |
| OFC048, ICO048 | Science, Innovation and Technology | Culture, Media and Sport | Ofcom and the Information Commissioner's Office are listed under the old DCMS group in FY2022-23; the current structure puts them with DSIT |
| PSH084, STS084 | Unallocated: former department lines | Science, Innovation and Technology | their lines are in the BEIS shared lines (U084) of the current-structure map |
| ELC011, ARA035 | Unallocated: former department lines | Small and Independent Bodies | the Electoral Commission and the Assets Recovery Agency no longer exist as current departments; their lines are Unallocated members of the map |

Also in the audit, not disagreements: 16 organisation codes (28 pairs) are in the bridge but not in the
newest BUD (for example `DEU077`, the Department for Exiting the European Union, now an Unallocated member,
and small bodies such as `LIL003` and `SDC003`), and 24 organisation codes are in the BUD but have no in-year
outturn pair (BUD-only bodies, mostly non-department central lines and small DCMS bodies).

## 2. Measures: `dw.plan_measure_selection` and `dw.outturn_plan_line`

`dw.plan_measure_selection` says which outturn lines each plan measure is. It is a definition written as
values in `sql/dw/552`:

| Measure | Control budget detail | Economic budget | Depreciation |
|---|---|---|---|
| RDEL | DEL PROG, DEL ADMIN | RESOURCE | in |
| RDEL_EX_DEPN | DEL PROG, DEL ADMIN | RESOURCE | PESA economic group DEPRECIATION left out |
| CDEL | DEL PROG, DEL ADMIN | CAPITAL | n/a |
| RAME | DEPT AME | RESOURCE | in |
| CAME | DEPT AME | CAPITAL | in |
| ADMIN | DEL ADMIN | RESOURCE | in |
| ADMIN_EX_DEPN | DEL ADMIN | RESOURCE | DEPRECIATION left out |

The measures overlap by design (ADMIN is part of RDEL; RDEL_EX_DEPN is RDEL less one group). Never add them.

`dw.outturn_plan_line` is the working table: the revision deltas of `dw.fact_outturn` summed to release x
period x organisation x control budget detail x economic budget x depreciation flag, with the group from
the bridge and the department number as the release reported it. Its sum equals `dw.fact_outturn`
(**tested**, 550).

## 3. The phasing profile: `dw.plan_phasing_profile` (DERIVED)

For a plan row in year Y the twelve monthly shares come from year Y-1's monthly outturn, as at the release
that closes Y-1 (`dim_release.is_year_end_release`): the sum of the revision deltas with `release_key` up to
that release. Period 0 (the 71 June 2019 rows with no month) is left out and the shares are renormalised over
periods 1 to 12. A profile matches the grain of the plan row it phases:

| Plan grain | Profile basis | Outturn lines |
|---|---|---|
| A (OSCAR Plans) | organisation | organisation code x control budget detail x economic budget |
| B, C, D (Estimates, PESA) | group | Spending Review group x measure through `dw.plan_measure_selection` and the bridge; the combined pre-2023 member is the lines of the three pre-2023 departments as the release reported them |

`method` records how each profile was made:

| Method | Rule |
|---|---|
| `prior_year_outturn` | share of a month = its outturn over the prior year's total, rounded to ten places; the rounding remainder goes to period 12, so the shares add up to exactly 1 |
| `flat_no_prior_year` | no year-end release exists for Y-1 (plan years before FY2019-20 and the years beyond the outturn), or the profile has no outturn line in Y-1: twelve flat twelfths |
| `flat_prior_not_positive` | Y-1 has outturn but its total is zero or negative: twelve flat twelfths |

A share can be negative (or above 1) when one month of the prior year was negative; `has_negative_share`
marks the profile. Plan years before FY2018-19 (FY2017-18 OSCAR Plans) have no calendar and are not phased.

Counts by method (profiles; negative-share profiles in brackets). Committed scope: `prior_year_outturn` 553
(223), `flat_no_prior_year` 167 (0), `flat_prior_not_positive` 29 (0), 749 in all. Full scope:
`prior_year_outturn` 2,331 (768), `flat_no_prior_year` 1,808 (0), `flat_prior_not_positive` 335 (0), 4,474 in
all. By plan year, `audit.plan_phasing_summary`. The two last plan years (FY2027-28 and FY2028-29, PESA only)
are all flat because the outturn does not reach their prior years.

**Tested**:
`sql/tests/552_profile_shares_sum_to_one_and_cover_twelve_periods.sql` (twelve periods, shares sum to exactly 1,
flat profiles are twelve twelfths, `has_negative_share` matches the shares, the stored prior-year amounts give
the shares to ten places),
`sql/tests/553_method_is_prior_year_wherever_a_positive_prior_year_exists.sql` and
`sql/tests/554_organisation_and_combined_profile_methods_recomputed.sql` (the method of every profile is
recomputed from `dw.fact_outturn` without the profile code, for group, organisation and combined profiles).

## 4. The phased plan: `dw.fact_plan_phased` (DERIVED)

One row per `dw.fact_plan` row and period 1 to 12, `scenario_key` the `Plan (phased)` member of
`dw.dim_scenario` (which is flagged derived), with the share and the method carried. `amount` is the plan
amount times the share rounded to four decimals for periods 1 to 11; period 12 takes the remainder, so the
twelve rows of a plan row add up to the plan amount with no difference. Administration rows
(`is_part_of_other_measure = 1`) are phased too and keep the flag: they are part of resource DEL and are never
added to it.

**Tested**: `sql/tests/555_phased_plan_sums_to_the_plan_exactly.sql` (every plan row with a calendar has
twelve rows, the sum equals the plan amount exactly, the keys and flags equal the plan row's, the period key
is inside the plan year, the scenario is `Plan (phased)` and the row is derived).

## 5. Outturn on the plan's basis

### In-year, `dw.outturn_plan_basis_inyear` (committed scope)

Release x financial year x period x Spending Review group (through the bridge) x measure. `amount` is the
outturn of that period as at that release: the running sum of the deltas of the release's financial year up
to and including the release, so it equals what the release reports. Rows that are exactly zero are not kept.
`is_year_end_release` marks the releases that close a year.

`basis_note` carries the caveat on the excluding-depreciation measures: the in-year files have no ringfence
column, so only the economic group DEPRECIATION is left out and other non-cash items stay in (about 5.5bn a
year from 2024-25, as profiled in `docs/profiling/cross-checks-and-deflators.md`). The exact basis is the
annual table below.

**Tested**: `sql/tests/556_inyear_plan_basis_equals_the_fact_selection_at_every_release.sql` recomputes every
release x group x measure from `dw.fact_outturn` (independent of `dw.outturn_plan_line`) and compares with the
table, and compares the year-end release totals of RDEL, CDEL, RAME and CAME with a direct selection.

### Annual, `dw.outturn_plan_basis_annual` (full scope)

Vintage x financial year x group x measure from `dw.fact_outturn_annual`, for every vintage:

- RDEL: DEL, resource;
- RDEL_EX_DEPN: `basis_rdel_excl_depreciation = 1` (DEL, resource, ringfence code not RINGFENCED), the basis
  the Estimates and the Spending Review use;
- CDEL: DEL, capital.

The group is the **BUD's own** Spending Review group of the organisation (`stg.bud_sr_group_by_organisation`),
not the bridge, so that the comparison reproduces the published groups. A group code the current list does
not have (the Foreign and Commonwealth Office, Exiting the European Union, the `n/a` of the central
exchequer lines) goes where `authored/plan_name_map.csv` puts that name; a group that matches neither stops
the build. `is_latest_vintage` and `is_latest_vintage_for_year` flag the newest release and the newest one
that holds the year.

**Tested** (full scope): `pipeline/tests/test_plan_phasing_sql.py::test_annual_plan_basis_reproduces_the_fy2023_24_bud_column`
reproduces the `BUD_23-24.xlsx (outturn)` column of `docs/profiling/data/plan_consistency_2023_24.csv` for
every group and measure in that file that has a figure (the vintage 2025-11 rows), to the thousand pound, and
the TOTAL (mapped groups) row (RDEL 476,202,577; RDEL_EX_DEPN 447,960,340; CDEL 104,115,801).

### In-year against annual (full scope)

`audit.plan_basis_inyear_vs_annual` (`evidence/full/plan_basis_inyear_vs_annual.csv`) sets, per financial year,
group and measure, the in-year figure at the year-end release against the annual figure of the newest
vintage that holds the year, with the gap. Nothing there passes or fails: the in-year June release is the
first look at the year, the annual file is restated, the in-year files lack the ringfence column, and the
bridge and the BUD can disagree on a group.

## FY2023-24 on one basis

Plan is the final-plan Estimate (the Supplementary Estimate). Annual outturn is `dw.outturn_plan_basis_annual`,
vintage 2025-11. In-year is `dw.outturn_plan_basis_inyear` at the June 2024 release (the one that closes the
year), through the bridge. GBP thousands. Produced from the full build by a query over `dw.fact_plan` and
`audit.plan_basis_inyear_vs_annual`; "annual minus plan" is my arithmetic, "in-year minus annual" is the
audit's gap. The Single Intelligence Account has no outturn, because OSCAR publishes none.

**RDEL excluding depreciation**

| Group | Plan | Annual outturn | In-year at year end | Annual minus plan | In-year minus annual |
|---|---:|---:|---:|---:|---:|
| Business and Trade | 1,900,922 | 1,715,281 | 1,687,499 | -185,641 | -27,782 |
| Cabinet Office | 913,201 | 736,775 | 895,780 | -176,426 | 159,005 |
| CLG Communities | 3,425,247 | 2,757,964 | 3,254,563 | -667,283 | 496,599 |
| CLG Local Government | 14,601,487 | 9,579,620 | 14,576,136 | -5,021,867 | 4,996,516 |
| Culture, Media and Sport | 1,598,438 | 1,508,563 | 1,556,765 | -89,875 | 48,202 |
| Defence | 35,001,212 | 33,473,664 | 33,486,595 | -1,527,548 | 12,931 |
| Education | 81,938,072 | 81,983,756 | 82,392,993 | 45,684 | 409,237 |
| Energy Security and Net Zero | 1,646,326 | 1,297,862 | 1,583,569 | -348,464 | 285,707 |
| Environment, Food and Rural Affairs | 4,823,185 | 4,748,371 | 4,741,365 | -74,814 | -7,006 |
| Foreign, Commonwealth and Development Office | 7,776,226 | 7,659,265 | 7,776,227 | -116,961 | 116,962 |
| Health (NHS) | 178,488,496 | 178,094,830 | 177,995,134 | -393,666 | -99,696 |
| HM Revenue & Customs | 5,992,637 | 5,968,810 | 5,969,244 | -23,827 | 434 |
| HM Treasury | 381,216 | 380,920 | 358,114 | -296 | -22,806 |
| Home Office | 19,239,683 | 19,013,089 | 22,844,490 | -226,594 | 3,831,401 |
| Justice | 10,483,116 | 10,421,125 | 10,440,307 | -61,991 | 19,182 |
| Law Officer's Departments | 882,741 | 840,921 | 836,688 | -41,820 | -4,233 |
| Northern Ireland | 14,847,116 | 14,803,885 | 14,803,110 | -43,231 | -775 |
| Science, Innovation and Technology | 336,128 | 454,205 | 288,198 | 118,077 | -166,007 |
| Scotland | 26,347,182 | 37,344,095 | 26,347,182 | 10,996,913 | -10,996,913 |
| Single Intelligence Account | 2,824,921 | | | | |
| Small and Independent Bodies | 2,482,815 | 2,417,793 | 2,384,805 | -65,022 | -32,988 |
| Transport | 8,203,965 | 7,892,240 | 7,892,586 | -311,725 | 346 |
| Wales | 16,453,273 | 16,468,519 | 16,492,256 | 15,246 | 23,737 |
| Work and Pensions | 8,551,341 | 8,398,787 | 8,398,784 | -152,554 | -3 |

**CDEL**

| Group | Plan | Annual outturn | In-year at year end | Annual minus plan | In-year minus annual |
|---|---:|---:|---:|---:|---:|
| Business and Trade | 1,397,037 | 1,068,399 | 1,197,997 | -328,638 | 129,598 |
| Cabinet Office | 648,015 | 411,729 | 456,996 | -236,286 | 45,267 |
| CLG Communities | 7,124,095 | 6,841,961 | 6,847,775 | -282,134 | 5,814 |
| Culture, Media and Sport | 603,687 | 529,927 | 589,952 | -73,760 | 60,025 |
| Defence | 19,196,726 | 17,933,585 | 17,898,687 | -1,263,141 | -34,898 |
| Education | 6,341,125 | 6,147,708 | 6,190,472 | -193,417 | 42,764 |
| Energy Security and Net Zero | 5,909,567 | 5,127,445 | 5,243,383 | -782,122 | 115,938 |
| Environment, Food and Rural Affairs | 2,112,646 | 1,984,115 | 2,054,888 | -128,531 | 70,773 |
| Foreign, Commonwealth and Development Office | 3,588,237 | 3,448,985 | 3,588,237 | -139,252 | 139,252 |
| Health (NHS) | 10,988,845 | 10,519,244 | 10,562,468 | -469,601 | 43,224 |
| HM Revenue & Customs | 751,178 | 725,117 | 747,178 | -26,061 | 22,061 |
| HM Treasury | 7,252 | 1,095 | 633 | -6,157 | -462 |
| Home Office | 1,539,841 | 1,297,686 | 1,510,896 | -242,155 | 213,210 |
| Justice | 1,518,494 | 1,458,412 | 1,453,395 | -60,082 | -5,017 |
| Law Officer's Departments | 48,100 | 38,282 | 38,282 | -9,818 | 0 |
| Northern Ireland | 2,138,124 | 2,108,785 | 2,120,146 | -29,339 | 11,361 |
| Science, Innovation and Technology | 12,607,989 | 12,438,150 | 12,350,336 | -169,839 | -87,814 |
| Scotland | 6,385,480 | 5,952,943 | 6,423,560 | -432,537 | 470,617 |
| Single Intelligence Account | 1,378,780 | | | | |
| Small and Independent Bodies | 413,359 | 309,054 | 357,916 | -104,305 | 48,862 |
| Transport | 22,149,471 | 22,093,725 | 22,142,318 | -55,746 | 48,593 |
| Wales | 3,119,224 | 3,047,012 | 3,045,566 | -72,212 | -1,446 |
| Work and Pensions | 691,008 | 632,442 | 632,443 | -58,566 | 1 |

What I can and cannot say about the gaps (none of this is tested beyond the figures above):

- Scotland: for RDEL excluding depreciation the annual figure is 11.0bn above the plan and the in-year
  figure equals the plan to the pound. The Foreign, Commonwealth and Development Office's in-year figure
  also equals its plan (exactly for CDEL, within 1 for RDEL excluding depreciation). Scotland's plan is
  published with a block grant adjustment flag (`dw.dim_plan_source.scotland_bga_flag`) and I have not
  reconciled the two, so I would not read Scotland's gap until that is done. I have not found out why the
  in-year files hold the plan figure for these lines.
- CLG Local Government: the in-year figure is 5.0bn above the annual one. The annual basis leaves out
  ringfenced items and the in-year files cannot, so I expect this to be the missing ringfence column, but I
  have not split the 5.0bn by economic category.
- Home Office RDEL excluding depreciation: the in-year figure is 3.8bn above the annual one (20%). I have not
  traced it.
- The small differences in the other groups are the first look against the restated annual figure.

## Nothing derived reaches a real total

**Tested**, two checks:

- `pipeline/tests/test_real_totals.py` compares the row count and the sum of each real fact (`dw.fact_outturn`,
  `dw.fact_plan`, and in full scope `dw.fact_outturn_annual`) with `evidence/expected/real_fact_totals.csv`, one set
  of rows per build scope. The committed-scope values (658,554 rows, 9,098,653,566.4360 for the outturn; 749 rows,
  7,785,863,653.0000 for the plans) are the ones recorded from a build of the branch point, before these files
  existed, and they are unchanged by this feature. A derived or authored object that added to or took from a real
  fact would move one of them and fail the test. The expected values used to be literals inside the SQL test; they
  are in one file so that a legitimate change is made in one place: rebuild, run `ukfr real-totals --write`, review
  the diff and commit it with the change that explains it. The same module's second test checks that exactly the
  phasing profile and the phased plan carry `is_derived` and that every row of both is flagged.
- `sql/tests/558_nothing_derived_reaches_a_real_total.sql` checks that the profile and the phased plan are
  flagged derived, that their table descriptions start with DERIVED, that no view, procedure or foreign key
  references `dw.fact_plan_phased`, and that the `Plan (phased)` scenario is the derived one.
`pipeline/tests/test_plan_phasing_sql.py::test_only_the_phasing_files_read_the_phased_plan` checks that the
only SQL files that name the phased plan are the one that builds it and its audit summary (and the `DROP`
that keeps the build re-runnable).

`sql/tests/559_no_float_in_the_phasing_objects.sql` checks that no table of this feature has a float, real
or money column, that every amount is `DECIMAL(19,4)` and every share `DECIMAL(19,10)`.

## Known limits

- The bridge follows the current structure. It reproduces the BUD's group for 255 of 283 organisation codes
  present in both and differs for the 28 above on purpose; where I should have kept the BUD's grouping instead, the authored file
  is the one place to change.
- Plans for FY2022-23 are on the pre-2023 department structure, so their groups (and the combined member)
  match the current outturn groups one to one only for the groups that did not change.
- Profiles are one prior year of outturn. They carry the prior year's seasonality, including a one-off, and
  do not know about it. A profile with a negative month is kept as it is.
- The in-year plan-basis outturn for the excluding-depreciation measures is not the exact basis; its note
  says so on every row.
- Not tested: nothing in this feature has been compared with a published monthly plan, because none is
  published.
