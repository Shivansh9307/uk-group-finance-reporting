# Plan sources for FY2022-23 onward

OSCAR stops publishing Plans after FY2021-22, so later plans come from HM Treasury's Estimates
"Departmental DEL budgets" tables, the PESA Chapter 1 tables and the Spending Review 2025 DEL tables.
This page records what those workbooks really contain and whether a plan by department group x
resource/capital DEL x year can be built from them for FY2022-23 to FY2026-27.

Everything here is **tested** unless marked **designed**. Command, run on 2026-11-16:

```
UKFR_DATA_DIR=<main checkout>/data/raw uv run --project pipeline ukfr profile plans
```

Reader: `ukfr.readers.plans` (tests in `pipeline/tests/test_plans.py`, on cells copied from the real
workbooks). Profiling: `ukfr.profile.plans`.

How the reader works, because it decides what the numbers mean:

- It reads the sheet XML itself (`read_workbook`), so no value passes through float arithmetic. Excel
  stores a number as the shortest text that round-trips a double, which can carry 16-17 significant
  digits (`16.128999999999998` in the 2022-23 Out-of-Turn RDEL table, `441.12399999999997` for its
  total). I round to 15 significant digits, the precision Excel shows, which gives back the typed value
  (`16.129`). A fast reader such as python-calamine also drops leading empty columns (it showed the
  Estimates names in column A; they are in column B), so positions from it are not the sheet's.
- `parse_table` finds the row of year labels (`2023-24`), the row of `plans`/`outturn` labels (above it
  in Estimates, below it in PESA), the unit cell, section headings, lines, totals and memo lines. A memo
  is a name one column to the right of the line names (`o/w block grant adjustments`) or a line that
  starts with "of which"; memos are never added into a total.
- `clean_name` strips footnote markers: trailing digits stuck to a word (`Home Office2`), bracketed
  markers anywhere (`Scottish Government (1), (3)`, `DLUHC (1) - Local Government`) and stray spaces
  (`Scottish Government3 `). It cannot tell a footnote from a real digit after a number: SR25 has
  `Transport - High Speed 27` (HS2 plus footnote 7), which the name map handles by alias.

## 10. Estimates DEL workbooks

Inventory: [`plan_estimates_inventory.csv`](data/plan_estimates_inventory.csv) (one row per workbook,
sheet and year). Every line as written and cleaned, with its value as published and in £000:
[`plan_estimates_names.csv`](data/plan_estimates_names.csv).

| Release | Sheets | Unit row / year row (1-based) | Year | Lines (RDEL / CDEL) | Published total minus sum of lines |
|---|---|---|---|---|---|
| 2022-23 Mains | `RDEL inc`, `RDEL ex`, `CDEL` | 3 / 4 | 2022-23 plans | 23 / 22 | +£1m to +£2m (3 dp rounding) |
| 2022-23 Out-of-Turn Supps | `RDEL inc`, `RDEL ex`, `CDEL` | 3 / 4 | 2022-23 plans | 23 / 22 | +£1m to +£2m |
| 2022-23 Supps | `RDEL inc`, `RDEL`, `CDEL` | 4 / 5 | 2022-23 plans | 23 / 22 | 0 to -£1m |
| 2023-24 Mains | `RDEL inc`, `RDEL ex`, `CDEL` | 3 / 4 | 2023-24 plans | 24 / 23 | -£1m to +£4m |
| 2023-24 Supps | `RDEL inc`, `RDEL ex`, `CDEL` | 3 / 4 | 2023-24 plans | 24 / 23 | 0 (6 dp) |
| 2024-25 Supps | `RDEL inc`, `RDEL ex`, `CDEL` | 3 / 4 | 2024-25 plans | 24 / 23 | 0 to -£1m |
| 2025-26 Mains | `RDEL inc`, `RDEL ex`, `CDEL`, `Direct impact of tax changes` | 3 / 4 | 2025-26 plans | 24 / 23 | -£1m to +£1m |
| 2025-26 Supps | `RDEL inc`, `RDEL ex`, `CDEL` | 3 / 4 | 2025-26 plans | 24 / 23 | 0 (6 dp) |
| 2026-27 Mains | `RDEL`, `CDEL` | 3 / 4 | 2026-27 plans | 24 + 2 memo / 23 | 0 (6 dp) |

- Units are £ billion everywhere except the 2025-26 tax-changes sheet (£ million), which is an
  allowance for employer National Insurance changes, not a budget; I leave it out of the plan.
- Each workbook has one year column, labelled `Plans`. No outturn columns.
- Every published total equals the sum of its lines to rounding: the 3-decimal workbooks are within
  £4m, the 6-decimal ones (2023-24 Supps, 2025-26 Supps, 2026-27 Mains) exactly.
- **Read the measure from the title, not the sheet name.** In 2022-23 Supps the sheet called `RDEL` is
  "Resource DEL excluding depreciation" (the other workbooks call it `RDEL ex`).
- **2026-27 Mains has no "excluding depreciation" table because its `RDEL` is on that basis.** Its
  lines match the excluding-depreciation plans in PESA December 2025 and SR25, not the
  including-depreciation ones (Defence 39.632 against PESA Dec 2025 RDEL ex 39.610 and RDEL incl.
  50.025; Transport 7.871 against 8.250 and 19.977). Its total, £520.017bn, equals PESA 2026 Table 1.3's
  2026-27 total resource DEL once reserves, the OBR shortfall allowance and the Budget Exchange
  adjustment are taken off (521,057 - 3,148 + 1,774 + 335 = 520,018). Two memo lines (`o/w block grant
  adjustments` under Scotland, `o/w depreciation` under Small and Independent Bodies) are excluded
  from the sum and the published total agrees.
- **Scotland is not on one basis.** The RDEL-including table carries the Scottish block grant
  adjustment (BGA, footnoted); the excluding-depreciation table usually does not (2022-23 Supps:
  £26.9bn including depreciation, £36.0bn excluding it, which cannot both be the same scope). 2023-24
  Supps is the exception: its RDEL-ex line, £26.3bn, includes the BGA, while PESA's outturn on the
  same basis is £37.4bn. The BGA is £8.9bn to £16.1bn a year (PESA 2026 Table 1.3). Scotland's plan
  needs a BGA flag and can only be compared with outturn on the same basis.

Department-group names as written (cleaned) in the CDEL tables, which shows the drift:

- 2022-23 (all three): includes Business, Energy and Industrial Strategy; Digital, Culture, Media and
  Sport; International Trade; "DLUHC Levelling up/Up, Housing and Communities" (the capital U changes
  between Mains and Supps); Scotland, Wales, Northern Ireland.
- 2023-24: BEIS, DCMS and DIT are replaced by Energy Security and Net Zero; Science, Innovation and
  Technology; Business and Trade; Culture, Media and Sport.
- 2024-25 onward: "MHCLG Housing, Communities and Local Government", "MHCLG Local Government",
  Scottish Government, Welsh Government, Northern Ireland Executive.
- Every year: Single Intelligence Account, which OSCAR's published data leaves out.
- RDEL tables have one more line than CDEL: DLUHC/MHCLG Local Government has no capital line.

**Best final plan per year** (the `best_final_plan_for_year` column): the last statutory budget for
the year is the Supplementary Estimate, so I take it where it exists.

| Year | Workbook | Why |
|---|---|---|
| 2022-23 | 2022-23 Supps (February 2023) | Final; the Out-of-Turn Supps (October 2022) only added £176m to BEIS on top of Mains |
| 2023-24 | 2023-24 Supps | Final |
| 2024-25 | 2024-25 Supps | Final; there is no Mains workbook for 2024-25 (PDF only) |
| 2025-26 | 2025-26 Supps | Final |
| 2026-27 | 2026-27 Mains | The 2026-27 Supps will not exist until February 2027 |

## 11. PESA Chapter 1 and SR25

Inventory: [`plan_pesa_inventory.csv`](data/plan_pesa_inventory.csv) (one row per workbook, sheet and
section); every department-group value: [`plan_pesa_values.csv`](data/plan_pesa_values.csv).

All PESA tables are £ million with the years in row 4 and `outturn`/`plans` in row 5. Department-group
tables (each line a group):

| Workbook | Years (outturn / plans) | Department-group tables |
|---|---|---|
| PESA 2022 | 2017-18 to 2021-22 / 2022-23 to 2024-25 | 1.3 RDEL and resource dept AME; 1.5 RDEL excl. depreciation; 1.7 admin, 1.7a admin excl. depreciation; 1.8 CDEL and capital dept AME; 1.10 TDEL; 1.12 TME; real-terms twins 1.4, 1.6, 1.9, 1.11, 1.13 |
| PESA 2023 | 2018-19 to 2022-23 / 2023-24 to 2024-25 | same set |
| PESA 2024 | 2019-20 to 2023-24 / 2024-25 | same set |
| PESA 2025 (July) | 2020-21 to 2024-25 / 2025-26 | same set, plus 1.16 RDEL excl. depreciation, 1.17 CDEL and 1.18 TDEL for 2026-27 to 2028-29 (2029-30 for CDEL): the Spending Review settlement |
| PESA 2025 (December update) | 2020-21 to 2024-25 / 2025-26 to 2028-29 | `Notes`, 1.3 to 1.11 (as above, renumbered: 1.5 RDEL excl. depreciation, 1.7/1.7a admin, 1.8 CDEL and capital AME, 1.10 TDEL), and Chapter 2 tables 2.1 (a)-(c) by economic category |
| PESA 2026 | 2021-22 to 2025-26 / 2026-27 to 2028-29 (2029-30 for CDEL) | 1.3 RDEL and resource dept AME; 1.5 admin; 1.6 CDEL and capital dept AME; 1.7 FTs and general capital; 1.9 TDEL; 1.11 TME; real-terms twins 1.4, 1.8, 1.10, 1.12; aggregates 1.1, 1.2, 1.13 (a)-(c), 1.14 |
| SR25 DEL tables | 2023-24 / 2024-25 to 2028-29 (2029-30 for CDEL), £ billion | 5.1 TDEL, 5.3 RDEL excl. depreciation, 5.4 CDEL, and a GDP deflator row (2024-25 = 1) |

**PESA 2026 does contain the Chapter 1 tables** (sheets `Table_1_1` to `Table_1_14`), contrary to the
earlier note that the file is broken at source. What it lacks is the separate "excluding depreciation"
tables: from PESA 2026 (as in 2026-27 Mains), Resource DEL itself is on the excluding-depreciation
basis (Health 2025-26 outturn 204,067 in PESA 2026 Table 1.3 against 203,376 excluding and 209,583
including depreciation in the December 2025 plans), and there is no admin-excluding-depreciation table.

Grain: every PESA plan is department group x measure x year. There is nothing below group level.

What PESA adds that the Estimates tables lack, and what the model should use:

- **Departmental AME plans** by group, resource and capital (PESA 1.3 and 1.6/1.8). Estimates DEL
  tables have none.
- **Administration budgets** by group (1.5 in 2026, 1.7/1.7a before).
- **Future years**: plans to 2028-29 (2029-30 for CDEL) from the July 2025, December 2025 and 2026
  editions and SR25. Estimates only ever give the current year.
- **Outturn on the same basis as the plans**, which is a second check on OSCAR outturn (question 13).
- It does not add a better current-year DEL plan: the July PESA "plans" for the year just starting are
  the Main Estimates figures (PESA 2023's 2023-24 plans equal 2023-24 Mains line for line: Education
  87,929, Health 178,578, Defence 41,011), so the Supplementary Estimate stays the final plan.
- Lines inside the department-group sections that are not departments must be kept out of the group
  plan: Reserves, the OBR allowance for shortfall, the Budget Exchange adjustment, the Scottish BGA
  line, unallocated funds (Levelling Up Fund, Growth Mission Fund, UK Shared Prosperity Fund ...) and
  in the TME tables debt interest, locally financed expenditure and accounting adjustments.
- Some groups are published as two lines with no parent line in the same table (PESA July 2025 1.17
  and SR25 5.4: "Transport (excl. High Speed 2)" and "Transport - High Speed 2"; the same for Energy
  Security and Net Zero and Sizewell C). They must be added up, not mapped separately.

## 12. Name mapping

Every distinct cleaned name from the Estimates tables, PESA department-group tables, SR25, the PSS
database and the `SR_GROUP_LONG_NAME` values of the latest BUD workbook (`BUD_24-25.xlsx`, November
2025 release, 23 groups), with the proposed BUD Spending Review group and a confidence flag:
[`plan_name_map_candidates.csv`](data/plan_name_map_candidates.csv) (177 rows). I read the BUD names
with python-calamine in a few lines (`profile.plans.bud_sr_groups`); the BUD reader itself is another
task's.

The BUD groups are: Business and Trade; CLG Communities; CLG Local Government; Cabinet Office;
Culture, Media and Sport; Defence; Education; Energy Security and Net Zero; Environment, Food and
Rural Affairs; Foreign, Commonwealth and Development Office; HM Revenue & Customs; HM Treasury;
Health (NHS); Home Office; Justice; Law Officer's Departments; Northern Ireland; Science, Innovation
and Technology; Scotland; Small and Independent Bodies; Transport; Wales; Work and Pensions.

Names that do not map one to one by spelling, and what I propose (the `ALIASES` table in
`profile/plans.py`, authored by me):

| Plan-source name | BUD SR group | Confidence | Note |
|---|---|---|---|
| Health and Social Care | Health (NHS) | high | the SR group for DHSC is named after the NHS |
| DLUHC Levelling Up, Housing and Communities; MHCLG Housing, Communities and Local Government; DLUHC/MHCLG - Housing and Communities | CLG Communities | high | renamed in 2024 |
| DLUHC Local Government; MHCLG Local Government; DLUHC/MHCLG - Local Government | CLG Local Government | high | resource only |
| Scotland, Scottish Government; Wales, Welsh Government; Northern Ireland, Northern Ireland Executive | Scotland; Wales; Northern Ireland | high | devolved administrations renamed from 2024-25; Scotland needs the BGA flag |
| HM Revenue and Customs | HM Revenue & Customs | high | |
| Law Officers' Departments | Law Officer's Departments | high | apostrophe placement differs |
| Transport (excl. High Speed 2) + Transport - High Speed 2 | Transport | high | parts: add them |
| Energy Security and Net Zero (excl. Sizewell C) + - Sizewell C | Energy Security and Net Zero | high | parts: add them |
| Business, Energy and Industrial Strategy (2022-23) | none | low | split in February 2023 into DESNZ, DSIT and Business and Trade |
| Digital, Culture, Media and Sport (2022-23) | Culture, Media and Sport | low | digital functions moved to DSIT |
| International Trade (2022-23) | Business and Trade | low | merged |
| Single Intelligence Account | none | none | not in OSCAR's published data: a plan with no outturn |
| Reserves, OBR allowance, Budget Exchange, unallocated funds, memo lines | none | n/a | not departments |

**GO/NO-GO: GO for FY2023-24 to FY2026-27, NO-GO for FY2022-23 one to one.** For FY2023-24 to
FY2026-27 every Estimates line maps to a BUD SR group with high confidence except the Single
Intelligence Account, which has no OSCAR outturn at all and must be carried as a plan-only group
(£3.5bn RDEL in 2023-24). For FY2022-23 three of 23 lines (BEIS, DCMS, International Trade; £19.9bn,
£0.7bn and £0.02bn of CDEL in Supps) are on the pre-February-2023 structure, while every BUD release
that covers 2022-23 is restated onto the new departments. A 2022-23 plan therefore needs either a
combined "BEIS + DCMS + DIT" comparison group (against DESNZ + DSIT + Business and Trade + Culture,
Media and Sport outturn) or a split the sources do not publish. No PESA edition gives 2022-23 plans
on the new structure: PESA 2023 already shows 2022-23 as outturn.

## 13. Consistency check: FY2023-24

[`plan_consistency_2023_24.csv`](data/plan_consistency_2023_24.csv): for every SR group and for RDEL
(including depreciation), RDEL excluding depreciation and CDEL, the 2023-24 Supps plan, PESA 2023's
2023-24 plan, PESA 2024's 2023-24 outturn and BUD 2023-24 outturn (November 2025 release), all mapped
through the name map and in £000. BUD "RDEL excluding depreciation" is resource DEL less the
`RINGFENCED` economic ringfence. Selected rows, £bn:

| Group | Measure | Supps plan | PESA 2023 plan | PESA 2024 outturn | BUD outturn |
|---|---|---|---|---|---|
| Education | RDEL incl. depreciation | 106.68 | 87.93 | 89.72 | 89.91 |
| Education | RDEL excl. depreciation | 81.94 | 81.69 | 81.79 | 81.98 |
| Health (NHS) | RDEL excl. depreciation | 178.49 | 173.51 | 177.93 | 178.09 |
| Defence | RDEL excl. depreciation | 35.00 | 32.21 | 34.78 | 33.47 |
| Transport | RDEL incl. depreciation | 20.36 | 17.04 | 18.52 | 19.59 |
| Transport | RDEL excl. depreciation | 8.20 | 6.93 | 7.90 | 7.89 |
| CLG Local Government | RDEL | 14.60 | 14.63 | 9.58 | 9.58 |
| Scotland | RDEL excl. depreciation | 26.35 | 36.72 | 37.45 | 37.34 |
| All mapped groups | RDEL excl. depreciation | 446.31 | 438.87 | 449.35 | 447.96 |
| All mapped groups | CDEL | 109.28 | 109.29 | 105.39 | 104.12 |

What this shows:

- **Units and sign**: Estimates £bn x 1,000,000 and PESA £m x 1,000 land on the same £000 scale as
  OSCAR, spending positive, and the plan and outturn columns are the same order of magnitude for every
  group.
- **OSCAR's resource DEL includes depreciation.** BUD resource DEL summed over all rows matches PESA's
  "Resource DEL" outturn (Health 182.82 against 182.63, Home Office 19.64 against 19.64), and BUD less
  the RINGFENCED ringfence matches PESA's "excluding depreciation" outturn (Health 178.09 against
  177.93, Education 81.98 against 81.79).
- **The plan to compare with is RDEL excluding depreciation.** Including depreciation, Education's plan
  is £16.8bn above outturn because of a non-cash ringfenced budget that is mostly unused; excluding it
  plan and outturn are within £46m. It is also the only basis available for every year: 2026-27 Mains and PESA 2026 only
  publish it, and SR25 controls it. Outturn for it is OSCAR resource DEL with `ECONOMIC_RINGFENCE_CODE
  <> 'RINGFENCED'` (BUD and the extracts); the in-year releases have no ringfence column, and the
  nearest they offer is PESA economic group `DEPRECIATION`, which misses impairments (see
  [cross-checks-and-deflators.md](cross-checks-and-deflators.md)).
- **The budget boundary is not quite the same.** Defence outturn is £1.3bn lower in BUD than in PESA
  (OSCAR's published data leaves out the operational costs of military operations, as the PSS metadata
  says), and SIA (£3.5bn) is in the plans but not in OSCAR. Scotland differs by the BGA.
- PESA 2023's plan is the Mains plan; Supps adds £7.4bn of RDEL ex depreciation in total.

## Decisions this supports

- GO: the final plan for each year is a single workbook: Supps for FY2022-23 to FY2025-26, Mains for
  FY2026-27 (`plan_estimates_inventory.csv`, `best_final_plan_for_year = yes`, 14 sheets).
- GO: plan by SR group x RDEL excl. depreciation / CDEL x year for FY2023-24 to FY2026-27, every line
  mapped except SIA (plan-only, £3.5bn RDEL in 2023-24).
- NO-GO: one-to-one mapping for FY2022-23; BEIS, DCMS and DIT (£20.6bn CDEL and £19.7bn RDEL
  excluding depreciation in 2022-23 Supps) need a combined comparison group.
- GO: departmental AME and admin plans by group from PESA (to 2028-29), at group grain only.
- GO: units and sign agree; the comparable resource measure is RDEL excluding depreciation, and OSCAR
  outturn on that basis is resource DEL less the RINGFENCED ringfence (£447.96bn against PESA's
  £449.35bn for 2023-24).

## What I would change in the design

- The plan says plan tables give "resource/capital DEL". Make the resource measure explicitly **RDEL
  excluding depreciation** for all years. RDEL including depreciation disappears from 2026-27 and
  makes Education look £17bn underspent.
- Add a `Plan basis` attribute (incl./excl. depreciation, BGA in/out) next to `Plan Source`, and a
  Scotland BGA flag.
- Carry SIA as a plan-only group rather than dropping it, so the plan total ties to the published
  Estimates total, and show its variance as "no outturn published".
- For FY2022-23, either show plan variance at a combined pre-2023 group for the three restructured
  departments or start Estimates-based variance at FY2023-24. I would start at FY2023-24 and show
  FY2022-23 plans at total DEL only.
- The note that the PESA 2026 Chapter 1 file is broken at source is wrong and should go; PESA 2026
  is the source for AME and admin plans to 2028-29.
