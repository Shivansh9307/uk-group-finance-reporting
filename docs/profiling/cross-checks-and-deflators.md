# Cross-checks and deflators

Two independent controls and the price indices: HM Treasury's Public Spending Statistics (PSS)
database, the three GDP deflator vintages, and ONS CPI (D7BT index, D7G7 annual rate).

Everything here is **tested** unless marked **designed**. Command, run on 2026-11-16:

```
UKFR_DATA_DIR=<main checkout>/data/raw uv run --project pipeline ukfr profile plans
```

Readers: `ukfr.readers.plans.read_workbook` (exact xlsx cells) for PSS and `ukfr.readers.deflators`
for the deflators and CPI (tests in `pipeline/tests/test_deflators.py`, on rows copied from the real
files). Profiling: `ukfr.profile.plans` (`pss_profile`, `deflator_rows`, `cpi_summary`).

## 14. Public Spending Statistics database (July 2026)

`PSS_Database_2026.xlsx` has three sheets: `Metadata`, `Pivot Table` (a pivot of the database) and
`Database`. The database sheet has one header row and **41,171 rows** in ten columns: `Year`,
`Economic Budget Code`, `Economic Ringfence Code`, `Control Budget Code`, `Control Budget Detail Code`,
`SR Group Long Name`, `Segment Code`, `Segment Long Name`, `PESA Economic Group Long Name`, `Amount`
(£000). Years are 2021-22 to 2025-26, all outturn. Control totals by year:
[`data/audit/pss_file_control_totals.csv`](../../data/audit/pss_file_control_totals.csv) (2021-22
£1,194.7bn ... 2025-26 £1,237.1bn), and they equal the workbook's own pivot sheet.

What it covers, from its metadata and confirmed in the numbers: DEL and departmental AME only (no
non-departmental AME, no non-budget), the Security and Intelligence Agencies removed, and the
operational costs of military operations removed, "to align to the treatment of the OSCAR transparency
release". Its grain is year x SR group x **segment** (the `S...` level-4 segment code, one level above
OSCAR's sub-segment) x PESA economic group x control budget detail x ringfence. There is no
organisation and no month. Its ringfence codes are `RINGFENCED RESOURCE`, `NON-RINGFENCED RESOURCE`,
`GENERAL CAPITAL`, `FINANCIAL TRANSACTIONS` and `SUME`; ringfenced resource is almost empty
(£0.1bn in 2021-22), so PSS resource DEL is on the excluding-depreciation basis.

Against the June in-year release for the same year
([`pss_vs_inyear.csv`](data/pss_vs_inyear.csv); in-year totals computed inline from the committed
releases; "excl. depreciation" drops in-year rows whose PESA economic group is `DEPRECIATION`):

| Year | DEL admin resource, excl. depreciation | DEL programme resource, excl. depreciation | DEL programme capital | Departmental AME resource |
|---|---|---|---|---|
| 2021-22 | -1.38% | -2.44% | -0.40% | +17.3% |
| 2022-23 | -0.80% | -2.74% | -1.22% | +46.1% |
| 2023-24 | -0.65% | -2.32% | -1.67% | +30.2% |
| 2024-25 | -0.17% | -4.29% | -0.75% | +29.7% |
| 2025-26 | -0.25% | -4.27% | -0.67% | +24.7% |

Against BUD by SR group (November 2025 release, which covers 2020-21 to 2024-25;
[`pss_vs_bud_by_group.csv`](data/pss_vs_bud_by_group.csv)), with BUD resource DEL less the RINGFENCED
ringfence and the PSS group names mapped through the plan name map:

- **CDEL agrees to within £0.5bn a year** in total (2023-24: PSS £103.67bn, BUD £104.12bn).
- **RDEL excluding depreciation, all groups except Scotland, agrees almost exactly from 2023-24**
  (2023-24: £410.637bn against £410.616bn, +£21m; 2024-25: -£96m) and within £2.6-3.3bn in the two
  earlier years.
- **Scotland is lower in PSS by the block grant adjustment** (2023-24: £26.08bn against £37.34bn, the
  £11.26bn BGA PESA 2026 publishes for that year). PSS takes the BGA off Scotland's resource DEL;
  OSCAR does not.
- Some money sits in a different group in PSS and BUD, netting to zero: 2023-24 Education -£4.10bn and
  Work and Pensions +£4.10bn; Home Office -£0.86bn and CLG Communities +£0.86bn.

The in-year gap in DEL programme resource is mostly the same BGA (2021-22 to 2023-24 the residual after
the BGA is -£1.6bn, -£0.5bn and +£1.2bn). From 2024-25 another £5.5bn remains, and since PSS and BUD
agree to £0.1bn there, it is the in-year side: dropping the `DEPRECIATION` economic group is not the
same as dropping the RINGFENCED ringfence (impairments and other non-cash items stay in). Departmental
AME does not reconcile at all (17-46%): PSS AME is not on the in-year release's basis, so it is not a
usable control for AME.

**GO/NO-GO: GO as an independent outturn control for DEL, at year x SR group x resource (excluding
depreciation) / capital, with expected gaps of under 0.1% in total from 2023-24 and under 1% before,
once Scotland is put on the same BGA basis; NO-GO for departmental AME.** It cannot check months or
organisations. Compared with the in-year releases (which lack a ringfence column) the control should
be run against BUD or the extracts, where `ECONOMIC_RINGFENCE_CODE` exists, or the expected gap
written down per year.

## 15. Deflators

### HMT GDP deflators, three vintages

[`deflator_vintages.csv`](data/deflator_vintages.csv): every financial year in every vintage, with the
published index, the per cent change, the chained index described below, money GDP and the sheet row.

| Vintage | Sheet | Base | Outturn to | Forecast years | Outturn source |
|---|---|---|---|---|---|
| June 2026 QNA | `30062026 deflator update` | 2025-26 = 100 | 2025-26 | 2026-27 to 2030-31 | ONS QNA, 30 June 2026; OBR March 2026 forecast |
| September 2026 QNA | `30092026 deflator update` | 2025-26 = 100 | 2025-26 | 2026-27 to 2030-31 | ONS QNA, 30 September 2026; OBR March 2026 forecast |
| October 2026 Budget | `28102026 deflator update` | 2025-26 = 100 | 2025-26 | 2026-27 to 2031-32 | ONS QNA, 30 September 2026; OBR October 2026 forecast |

Layout, the same in all three: one sheet; column A empty; title in B1; two note lines (their order
differs: the Budget file puts the forecast note first); the header block on rows 5-7; financial years
in column B from 1955-56 on row 8, with the index (`2025-26 = 100`) in C, the per cent change in D and
money GDP not seasonally adjusted and seasonally adjusted (£ million) in E and F; a calendar-year block
from column H; sources and footnotes below the last year. The reader finds the header row and columns
by their text, not by position.

Forecast years are labelled with footnote markers (`2026-27 (1), (2)`) and have `-` in the index
column: only the per cent change is published.

The same years in the three vintages:

| Year | June index | September index | October index | June % change | October % change |
|---|---|---|---|---|---|
| 2017-18 | 74.4665 | 74.6091 | 74.6091 | 1.27 | 1.22 |
| 2020-21 | 82.2588 | 82.3141 | 82.3141 | 5.23 | 5.12 |
| 2022-23 | 88.2512 | 88.4564 | 88.4564 | 7.03 | 7.01 |
| 2024-25 | 96.6694 | 96.7570 | 96.7570 | 4.06 | 3.93 |
| 2025-26 | 100 | 100 | 100 | 3.45 | 3.35 |
| 2026-27 | - (chained 102.0057) | - (102.0057) | - (102.6328) | 2.01 | 2.63 |

This contradicts what I expected to show. **The three vintages are not rebased: all three use
2025-26 = 100.** The differences are revisions: September's QNA revised the whole outturn history
(2017-18 from 74.4665 to 74.6091), and the October Budget kept September's outturn and replaced the
OBR forecast (2026-27 from 2.01% to 2.63%). A rebasing does appear elsewhere in my files: the SR25
DEL tables carry a deflator row at 2024-25 = 1 (2023-24 0.9634), and HMT moves the base year each
spring when a new year of outturn arrives.

**Recommendation (designed).** Build one real-terms index from one vintage: take the published
outturn index as it stands and chain each forecast year from the year before with its published per
cent change (`deflators.chained_index`, rounded to four decimals at each step, tested to give
102.6328 and 104.8078 for 2026-27 and 2027-28 in the Budget vintage). Never mix index levels from two
vintages. **Default vintage: October 2026 Budget**, the latest outturn (30 September 2026 QNA) and the
latest forecast, and the vintage the next Estimates and PESA will use. Keep the other two in a
`Deflator Vintage` dimension to show how revisions move real-terms growth. To restate at another base
year, divide by that year's index.

### ONS CPI (D7BT index, D7G7 annual rate)

The generator CSVs have one block structure: 8 metadata lines (`Title`, `CDID`, `Source dataset ID`,
`PreUnit`, `Unit`, `Release date`, `Next release`, `Important notes`), then the annual block, the
quarterly block and the monthly block, one value per line, no blank lines between blocks.

| Series | Title | Release date | Annual | Quarterly | Monthly | Latest |
|---|---|---|---|---|---|---|
| D7BT | CPI INDEX 00: ALL ITEMS 2015=100 | 21-10-2026 | 1988-2025, from line 9 | 1988 Q1-2026 Q3, from line 47 | 1988 JAN-2026 SEP, from line 202 | 2026 SEP = 144.1 |
| D7G7 | CPI ANNUAL RATE 00: ALL ITEMS 2015=100 | 21-10-2026 | 1989-2025, from line 9 | 1989 Q1-2026 Q3, from line 46 | 1989 JAN-2026 SEP, from line 197 | 2026 SEP = 3.5 |

The two series start in different years, so the blocks start on different lines. `read_ons_series`
therefore classifies each line by the shape of its first field (`1989`, `1989 Q1`, `1989 JAN`) instead
of by position, fails if a non-data line appears after the data starts, checks the blocks come in the
order annual, quarterly, monthly, and checks the months are strictly increasing. The monthly block is
the one to load; the last line is the latest month.

## Decisions this supports

- GO: PSS 2026 as an independent DEL outturn control at year x SR group x RDEL excl. depreciation /
  CDEL, FY2021-22 to FY2025-26; total gap against BUD +£21m in £410.6bn (2023-24, Scotland excluded).
- NO-GO: PSS as a control for departmental AME (17-46% off the in-year releases) or below SR group.
- Scotland needs a BGA adjustment (£11.26bn in 2023-24) before any PSS or plan comparison.
- GO: one real-terms index per vintage, published outturn plus chained forecast changes; default the
  October 2026 Budget vintage (2025-26 = 100, outturn to 2025-26, forecast to 2031-32).
- GO: ONS CPI monthly block picked by the shape of the date field; latest month 2026 SEP (D7BT 144.1).

## What I would change in the design

- The plan says the three deflator vintages show "the base-year shift". They do not: all three are
  2025-26 = 100. Describe them as revisions (outturn revised by the September QNA, forecast replaced
  by the Budget). If a rebasing example is wanted, use the SR25 deflator row (2024-25 = 1) or the next
  spring's vintage.
- The plan parses the deflator files in Power Query by sheet position. Column A is empty, the note
  lines change order between vintages and forecast years carry `-`; parse by header text, as the
  Python reader does, or load the tidy table from SQL.
- The PSS control belongs against BUD or the extracts, where the ringfence column exists. Against the
  in-year releases it carries a known gap (the BGA plus about £5.5bn of non-depreciation ringfenced
  items from 2024-25) that the data controls page must state per year.
