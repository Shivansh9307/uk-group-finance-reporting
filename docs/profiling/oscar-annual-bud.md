# Profiling: OSCAR annual restated ("BUD") files

HM Treasury's annual OSCAR releases include one workbook per financial year, restated onto the
department structure current at the time of the release. I have three vintages (November 2023,
2024 and 2025), each holding five years, so 15 workbooks covering 2018-19 to 2024-25. This page
says what is in them, how to total them correctly, what their machinery-of-government layer shows,
which mapping tables they give the model, and whether they can serve as an independent control for
the in-year fact ([oscar-inyear.md](oscar-inyear.md)).

Everything here comes from one command, run on 16 November 2026 (**tested**):

```
UKFR_DATA_DIR=<folder holding the fetched files> uv run --project pipeline ukfr profile bud
```

It reads the 15 workbooks from `$UKFR_DATA_DIR/oscar_annual_bud/`, the June in-year releases from
the repository, and the PESA December 2025 tables from `$UKFR_DATA_DIR/pesa/` for one published
check. It takes about 1 minute 45 seconds (each workbook takes 4 to 6 seconds to read) and writes
the CSVs named below. Run `ukfr profile inyear` first: the BEIS cross-check reads one of its outputs.

## The reader

`ukfr.readers.oscar_bud.read_bud(file, repo_root)` reads a workbook with `python-calamine` 0.9.1
(binary wheel for CPython 3.14 on Windows, no build step), checks the 91-column header exactly,
returns every cell as text (whole numbers without `.0`) and AMOUNT as an exact `Decimal`. A sheet
with data but another header, or no sheet with the BUD header, raises `BudFormatError` (**tested**,
`pipeline/tests/test_oscar_bud.py` on a workbook built from two published rows). calamine returns
numbers as doubles; every AMOUNT in the 15 files is a whole number (all 515,949 rows are
`number_integral`), so the conversion is exact, and the reader counts any non-integral value as
`number_fraction` so a future file that breaks this is visible.

## 13. What each file holds

[`data/audit/bud_file_control_totals.csv`](../../data/audit/bud_file_control_totals.csv) has one
row per workbook; [`bud_file_control_totals_by_layer.csv`](../../data/audit/bud_file_control_totals_by_layer.csv)
splits each total by TYPE_CODE, STATUS_CODE, TYPE × STATUS, control budget levels 0 and 1, economic
budget, version and month (**tested**).

- All 15 workbooks have the identical 91-column header. The November 2023 files hold one sheet
  named `in`; the 2024 and 2025 files hold `Transparency_report_BUD_REPORTI` plus an empty `Sheet1`.
  Rows per file: 30,074 to 39,861; no blank rows.
- Every row has VERSION_CODE `Outturn` and MONTH and QUARTER `P00`: annual figures only.
- STATUS_CODE: `Confirmed` everywhere; `Submitted`, `Locked` and `Closed` in some files.
- TYPE_CODE: 3 to 12 values per file. The November 2023 vintage holds migrated layers
  (`TYPE_MIGR_INYEAR`, `TYPE_MIGR_OUTTURN`, `TYPE_MIGR_NEUTRAL`, `TYPE_MIGR_SWITCH`,
  `TYPE_MIGR_MOG`, `TYPE_MIGR_MOGDISAG`); later vintages keep those for the older years and add
  `TYPE_INYEAR`, `TYPE_OUTTURN`, `TYPE_MOG`, `TYPE_MOG_R`, `TYPE_MOGDISAG`, `TYPE_BRC`,
  `TYPE_AME`, `TYPE_NONBUDGET` and `TYPE_PESA_ADJUSTMENT_LIVE`.

**The rule for a correct total**: sum every TYPE layer (they are reasons for change that stack,
not alternatives), and exclude rows with STATUS_CODE `Closed`. Each `Closed` row has an identical
twin, every column but STATUS equal, under another status (3 to 6 per file, 35 in all, every one
twinned: `closed_rows_with_identical_twin` equals `closed_rows`), and the `TYPE_MOG` /
`TYPE_MOG_R` pairs only net to zero once the Closed rows are left out. `Submitted` and `Locked`
rows have no twins and must stay in. The effect of the exclusion is small (£1.1m to £5.5m per file).

**Checked against a published figure**: the "Understanding OSCAR" notes for 2023, 2024 and 2025
under `$UKFR_DATA_DIR` publish no totals (I read all three), so I used PESA's December 2025 update
(Tables 1.3 and 1.8, £ million), which HM Treasury published a month after the November 2025
vintage. [`bud_pesa_check.csv`](data/bud_pesa_check.csv):

| Line | 2020-21 | 2021-22 | 2022-23 | 2023-24 | 2024-25 |
|---|---|---|---|---|---|
| Resource departmental AME, BUD minus PESA | +£3.6m | -£109.3m | -£10.8m | -£14.3m | +£1,181.9m |
| Capital departmental AME | -£0.1m | +£0.4m | +£0.3m | -£1.7m | -£573.6m |
| Resource DEL | -£3,077m (-0.6%) | -£3,362m (-0.7%) | -£4,036m (-0.9%) | -£4,798m (-1.0%) | -£5,438m (-1.1%) |
| Capital DEL | -£630m (-0.7%) | -£908m (-1.0%) | -£3,211m (-3.2%) | -£2,592m (-2.4%) | -£3,030m (-2.7%) |

Departmental AME reproduces the published figures to within rounding (under £2m) for capital and
within £15m for resource in three of four closed years, which confirms the layer rule. DEL is
consistently below PESA by 0.6% to 3.2%. The PESA notes say its DEL totals include adjustments made
at Budget, and the devolved administrations' resource DEL is "adjusted for the devolution of tax and
welfare powers"; I have not split the DEL gap by department, so that explanation is **designed, not
tested**. 2024-25 is the newest year and moved between November and December 2025.

## 14. HM Treasury's machinery-of-government layer

[`bud_mog_movements.csv`](data/bud_mog_movements.csv) lists every row whose TYPE_CODE contains
`MOG`, summarised by year, vintage, type, status, department group and organisation (374 rows). The
`COUNTER_ORGANISATION_CODE` column is blank in every file, so a movement's other side has to be
inferred: `TYPE_MOG` rows sit on the giving organisation (negative) and `TYPE_MOG_R` rows on the
receiving one (positive), and the two net to zero apart from Closed rows; `TYPE_MOGDISAG` nets to
zero by itself (a reallocation inside the receiving body).

What the layer shows (November 2025 vintage unless stated):

- 2020-21: a `TYPE_MIGR_MOG` move from the Foreign and Commonwealth Office group (-£2.95bn) to FCDO
  (+£2.96bn): the FCO/DFID merger. Also £17.6bn passing from MHCLG to the Cabinet Office and back in
  the migrated layers, netting to zero.
- 2020-21: `TYPE_MOG` from the DSIT group (-£4.16bn, i.e. the old BEIS code) to DESNZ (+£3.53bn)
  and DBT (+£0.63bn): part of the 2023 BEIS split, restated back.
- Every year 2020-21 to 2023-24: MHCLG to the Department for Education (£0.16bn to £0.24bn a year)
  and Cabinet Office outflows to DSIT, HM Treasury and Defence (£0.12bn to £0.29bn).

**Does it agree with question 12?** In direction, yes: FCO into FCDO and BEIS into DESNZ/DBT/DSIT
are both there. In size, no: the layer carries £4.2bn for the BEIS split in 2020-21, while the
in-year June 2021 file puts £46.6bn of 2020-21 DEL on organisation codes that sit in the DSIT group
of the restated file, which itself shows £10.9bn for DSIT, £10.4bn for DESNZ and £22.7bn for DBT
(question 16). Most of a restatement is done by
recoding the data itself, not through MOG rows, and renames (MHCLG/DLUHC) need no MOG row at all.
The MOG layer is a partial log, not a list of reorganisations.

## 15. Mapping tables for the model

From all 15 workbooks, with a flag for the latest vintage and a count of variants per code
(**tested**):

- [`bud_department_group_map.csv`](data/bud_department_group_map.csv): DEPARTMENT_GROUP_CODE →
  name → SR group → PESA group. The latest vintage has 67 department groups, 25 SR groups and 24
  PESA groups. Two things the plan's join must handle: `CLG085.GROUP` maps to two SR groups
  ("CLG Communities" and "CLG Local Government"), so department group → SR group is not a function
  for MHCLG; and three codes change between vintages: `CLG085.GROUP` is named DLUHC in the 2023
  vintage and MHCLG later, `OFQ070.GROUP` moves from SR group Education to Small and Independent
  Bodies in 2025, and `UKP905.GROUP` (UKAEA pensions) moves from DSIT to DESNZ in 2025.
- [`bud_organisation_type.csv`](data/bud_organisation_type.csv): ORGANISATION_CODE → organisation
  type L1 and department group. 321 codes, 307 in the latest vintage: 223 arm's-length bodies, 55
  departments, 11 public corporations, 8 pension schemes, 5 local government, 3 devolved
  administrations, 2 designation-order bodies. No code changes type or group between vintages or
  years (each vintage is restated onto its own structure).
- [`bud_account_hierarchy.csv`](data/bud_account_hierarchy.csv): economic category → economic group
  → economic budget, with the number of chart-of-accounts L5 codes under each. 128 categories in 75
  groups; none changes between vintages. Every in-year economic category is in the BUD except the
  placeholder `NA` (the BUD writes `n/a`).

**In-year organisation codes in the BUD**: of the 222 codes in the latest in-year release
(September 2026), 216 are in the November 2025 BUD organisation list
([`bud_inyear_org_match.csv`](data/bud_inyear_org_match.csv)). The six that are not are bodies set
up after 2024-25: Great British Energy (`GBE066`), Building Safety Regulator (`BSR085`), Independent
Football Regulator (`IFR048`), Liverpool Bay CCS (`LBC066`), Lottery Community Fund (`LCF048`) and
Livestock Information (`LIL003`).

## 16. Reconciliation between the two families

For each year in both families I compared the June in-year release (full year, final for in-year)
with the BUD outturn for that year from every vintage that holds it: in total, by control budget
([`bud_inyear_reconciliation_total.csv`](data/bud_inyear_reconciliation_total.csv)), and by
department group and control budget
([`bud_inyear_reconciliation_department.csv`](data/bud_inyear_reconciliation_department.csv)).
In-year rows are given a department group through their organisation code in the same BUD file;
only 7 small in-year codes find no match in any year (£32m in 2019-20, zero elsewhere).

Gap = in-year minus BUD, latest vintage holding the year (**tested**):

| Year | Vintage | DEL | AME | Non-budget | Total |
|---|---|---|---|---|---|
| 2018-19 | 2023-11 | -0.1% | -35.4% | -90.0% | -60.6% |
| 2019-20 | 2024-11 | -2.5% | -10.7% | -58.3% | -18.8% |
| 2020-21 | 2025-11 | +0.1% | -10.3% | -92.1% | -25.5% |
| 2021-22 | 2025-11 | +0.8% | -9.3% | -89.1% | -23.6% |
| 2022-23 | 2025-11 | +1.4% | +8.0% | -92.2% | -22.2% |
| 2023-24 | 2025-11 | +3.4% | -3.4% | -84.8% | -24.1% |
| 2024-25 | 2025-11 | +0.9% | -4.4% | -2.2% | -1.7% |

What explains the gaps:

- **Non-budget is a different boundary.** The restated files carry large non-budget layers the
  in-year files do not (for 2018-19, £1.13tn of non-budget; the `TYPE_MIGR_NEUTRAL` layer alone
  sums to £1.13tn in that file). Only for
  2024-25, the year not yet restated by a later vintage, does non-budget line up (-2.2%).
- **AME moves after June.** Provisions, impairments and pension-scheme adjustments are loaded after
  the in-year June snapshot, in both directions (-35% to +8%).
- **The June snapshot is not final outturn.** The annual-extract profiling (T04b,
  `oscar-annual-extracts.md`) found the June in-year snapshot differs from the final R13 return by
  up to 2.7% of DEL programme in FY2020-21; part of the DEL gap here is that post-June movement,
  not a boundary difference.
- **DEL is close.** Within -2.5% to +3.4% in total for every year on the latest vintage (-3.2% to
  +3.4% across all vintages), and within 1% in four of seven.
- **Department level breaks on reorganisations.** Mapping in-year codes to the restated structure
  by organisation code sends all BEIS-core spending to DSIT (the code's current owner), so DSIT is
  overstated and DESNZ understated in every year before 2023-24 (2022-23 against the November 2023
  vintage: DSIT +£21.3bn, DESNZ -£20.4bn). Outside reorganisations, the largest DEL gap in 2024-25 is the Home Office (+£4.5bn,
  +30%), which I have not explained.

Department-level DEL, all department groups, latest vintage (from the department CSV):

| Year | Groups | Share of BUD DEL value within 1% | Within 5% | Σ\|gap\| / Σ\|BUD\| |
|---|---|---|---|---|
| 2018-19 | 51 | 78% | 93% | 3.8% |
| 2019-20 | 50 | 51% | 67% | 8.5% |
| 2020-21 | 52 | 60% | 85% | 14.6% |
| 2021-22 | 51 | 68% | 90% | 9.3% |
| 2022-23 | 51 | 64% | 87% | 9.5% |
| 2023-24 | 51 | 53% | 76% | 3.9% |
| 2024-25 | 51 | 70% | 97% | 1.4% |

**Restatement between vintages** ([`bud_vintage_restatement.csv`](data/bud_vintage_restatement.csv)):
for 2019-20 to 2021-22 the file total moves by under 0.1% between vintages and only 3 or 4 of about
66 department groups move by more than 1%. 2022-23 is different: the total rises 9.7% between the
November 2023 and November 2025 vintages, almost all in the Department of Health group
(£130.6bn to £254.4bn; I did not split that by layer), and 22 groups move by more than 1%. 2023-24 rises 1.8%
between its two vintages (17 groups over 1%). At DEL level the vintages differ by -1.8% to +0.04%.

## Decisions this supports

- **GO** on summing the BUD by including every TYPE layer and excluding `Closed`: departmental AME
  then matches PESA December 2025 to within £15m (resource) and £2m (capital) for three of four
  closed years; 35 Closed rows, all duplicates.
- **GO** on the BUD as an independent control for in-year **DEL at total level**, every year: gap
  -3.2% to +3.4% across all 15 year-vintage pairs (within 1% in four of seven years on the latest
  vintage).
- **NO-GO** on the BUD as a control for in-year **AME, non-budget or the grand total**: gaps up to
  -35% (AME), -92% (non-budget) and -61% (total), from boundary and post-June adjustments.
- **NO-GO** on the BUD as a hard department-level control, except as a tolerance check for the
  newest year: 97% of 2024-25 DEL value within 5%, but only 67% to 93% in earlier years, and
  reorganised departments need the sub-segment map first.
- **NO-GO** on HM Treasury's MOG rows as the list of reorganisations: £4.2bn of MOG rows against
  £46.6bn of BEIS DEL restated in 2020-21; the counterparty column is always blank.
- **GO** on the BUD department-group, organisation-type and account tables as model mappings: 0
  type or group changes across vintages for 321 organisation codes, 0 changes for 128 economic
  categories; 216 of 222 current in-year organisation codes found.

## What I would change in the design

- Reconcile in-year to BUD on DEL only, with a stated tolerance (I would use 3.5% at total level,
  which all 15 year-vintage pairs pass), and publish AME and non-budget as "boundary differences" rather than
  failures.
- Map department group to SR group per organisation, not per department group, because
  `CLG085.GROUP` splits into two SR groups; the plan's `DEPARTMENT_GROUP_CODE` → `SR_GROUP_LONG_NAME`
  map would have to pick one.
- Use the latest vintage for the "current structure" restatement check, and record the vintage on
  every comparison: the same year moves by up to 9.7% between vintages.
- Do not derive the BEIS split from the BUD; use it as the independent check it is suited for (the
  cross-check in [organisation-keys.md](organisation-keys.md) agrees for 178 of 204 sub-segments).
