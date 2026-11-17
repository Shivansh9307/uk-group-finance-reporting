# Profiling: OSCAR II in-year releases

I profiled all 31 in-year releases (March 2019 to September 2026, 32 files: March 2026 is published
twice, as a zip holding an ODS and as a bare ODS) to decide two things before any warehouse code
exists: whether the core fact can store revision deltas at release × organisation × sub-segment ×
economic category × control budget × month, and what the calendar has to hold. Organisation codes
are in [organisation-keys.md](organisation-keys.md); the annual restated files and the
reconciliation between the two families are in [oscar-annual-bud.md](oscar-annual-bud.md).

Every number on this page comes from one command, run on 16 November 2026 (**tested**):

```
uv run --project pipeline ukfr profile inyear
```

It reads only the committed files under `data/committed/oscar_inyear/` (no `UKFR_DATA_DIR`
needed), takes about two minutes, and rewrites every CSV named below. Sums are `Decimal` under a
context that raises on any rounding, rows are sorted, and a second run produces byte-identical
files (**tested**: `test_end_to_end_control_totals_deltas_and_determinism` runs it twice on a
two-release fixture repository and compares bytes; on the real releases I ran it twice in separate
processes with different `PYTHONHASHSEED` values and every output had the same sha256, after fixing
one tie in the order of the durable-key candidates that had depended on set order).

## The reader

`ukfr.readers.oscar_inyear.read_inyear(file, repo_root)` yields one canonical row per data line of
any release, whatever the packaging (zip with CSV, bare CSV, zip with ODS, bare ODS). What it does
(**tested**, `pipeline/tests/test_oscar_inyear.py`, 20 tests on snippets cut from each layout):

- maps the header to canonical names through `HEADER_VARIANTS`; an unknown header, a populated
  column beyond the header, an undecodable byte or an amount it cannot read exactly raises
  `InyearFormatError`;
- decodes CSV as Windows-1252 and keeps line breaks inside quoted fields as one record;
- reads ODS by parsing `content.xml` itself, so the amount is the exact `office:value` text, and
  expands rows the writer compressed with `number-rows-repeated`;
- parses Amount to `Decimal` and records its form (`plain`, `thousands_separator`, `scientific`,
  `parentheses`, `trailing_minus`, `blank`; ODS forms are prefixed `ods_float_`);
- strips spaces and line breaks around fields and counts how many it stripped;
- drops fully blank rows, counting them and how many trail the last data row;
- keeps Year, Quarter and Month raw and derives `financial_year` and `period` (April = 1) from
  Month; a Month that is not a calendar month gives period 0, it is not dropped;
- attaches the release label from `data/manifest/files.csv` (`list_inyear_files`).

## 1. Per release: the control table

[`data/audit/inyear_file_control_totals.csv`](../../data/audit/inyear_file_control_totals.csv) has
one row per data file (32 rows), fixed column order, exact sums. `primary_for_release` marks the
file I would load for each release; for March 2026 that is the zip, and
[`inyear_twin_files.csv`](data/inyear_twin_files.csv) shows the bare ODS holds the identical 53,604
rows (same multiset of rows and amounts), so the duplicate costs nothing but must not be loaded
twice. Raw-value splits by control budget and economic budget are in
[`inyear_file_control_totals_by_budget.csv`](../../data/audit/inyear_file_control_totals_by_budget.csv).

What the table shows (**tested**):

- 1,547,078 data rows across the 31 primary files; 1,324,769 blank rows dropped, of which 994,971
  are the empty tail of the March 2026 ODS sheet (1,048,575 sheet rows). Eleven CSV releases also
  carry blank trailing rows (`,,,,` lines), up to 62,952 in March 2020. No blank row sits between
  data rows.
- Encoding: no CSV is valid UTF-8; byte 0x92 (right single quote in Windows-1252) is in all 30
  CSV releases, and 0x96, 0xA0, 0xC6 and 0xE1 appear in later ones. All decode as cp1252.
- Line breaks inside quoted fields: 349 rows in the eight releases from September 2019 to June
  2021, all a trailing `\n` at the end of a sub-segment name (stripped).
- Amount forms: 1,420,797 plain; 126,214 with thousands separators (2019-03 to 2020-09 and again
  2025-06 to 2025-12); 67 in scientific notation (2023-03, 2024-03, 2024-06, 2026-03, 2026-06,
  2026-09); none in parentheses, with a trailing minus, or blank.
- Non-integer amounts appear from March 2023: 22,447 rows in 12 releases. 14,959 of them have more
  than four decimal places, and the scientific ones are binary floating-point residue such as
  `-1.06581E-14` and `1.13687E-13`. Rounding each amount to four places (what `DECIMAL(19,4)` will
  store) moves a file total by at most 0.0054 (£5.44); both sums are in the table
  (`amount_sum`, `amount_sum_rounded_4dp`), and the load test should compare against the rounded one.
- Every row maps to DEL, AME or NON-BUDGET and to RESOURCE, CAPITAL, OTHER NON-BUDGET or N/A
  (`amount_cb_other` and `amount_eb_other` are zero in every file).

## 2. Header variants and value domains

[`inyear_header_variants.csv`](data/inyear_header_variants.csv) maps every source column to its
canonical name; [`inyear_value_domains.csv`](data/inyear_value_domains.csv) lists every value of
the code columns with first and last release and row counts (**tested**).

| Variant | Releases | Differences |
|---|---|---|
| `v2019` | 2019-03 to 2021-06 (10) | 17 columns: has `PESA Economic Group Long Name` |
| `v2021sep` | 2021-09 (1) | 16 columns, renamed: `Organisation Name`, `Control Budget Detail`, `Department`, `Sub-segment Code/Name`, `Economic Category Name`, `Economic Budget`, `Version Snapshot` |
| `v2021dec` | 2021-12 to 2022-12 (5) | as `v2021sep` but `Control Budget` instead of `Control Budget Code` |
| `v2023` | 2023-03 to 2026-09 (15) | 16 columns, the current names |

Value-domain changes do not line up with header changes:

- Control budget: `DEL`, `AME`, `NON-BUDGET` to September 2022; `TOTAL DEL`, `TOTAL AME`,
  `TOTAL NON-BUDGET` from December 2022 (a header change came only in March 2023). Control budget
  detail (`DEL ADMIN`, `DEL PROG`, `DEPT AME`, `NON-DEPT AME`, `NON-BUDGET`) never changes.
- Economic budget: `n/a` to June 2021, `NA` from September 2021; the `NA` economic category's
  economic budget is `OTHER NON-BUDGET` before December 2022 and `NA` after.
- Version: `RETURNn_MON` to June 2021, except June 2019 and June 2021, which are `OUTTURN`;
  `MFO_<year>_Rnn_...` from September 2021, with free-text suffixes (`PSF_v5 - WD9 1730`). Every
  release holds exactly one Version value.
- Names change case: upper case to June 2021, mixed case from September 2021.

## 3. Time

[`inyear_time_values.csv`](data/inyear_time_values.csv) lists every (release, Year, Quarter, Month)
with rows, amount and flags; [`inyear_release_windows.csv`](data/inyear_release_windows.csv)
compares each release with its expected window (**tested**).

- Every release covers exactly its expected year to date: September = periods 1-3, December = 1-6,
  March = 1-9, June = 1-12 of the previous year. No release holds a month from another financial
  year, and none holds a month beyond its window.
- One non-month period exists: June 2019 has 71 rows whose Month and Quarter are
  `Period 0 - 18-19` (£269.9m net: Crown Estate Office £236.4m, Northern Ireland Executive
  £47.2m, DWP -£13.7m; Version `OUTTURN`). No release has a
  period 13, 14 or an adjustment month, although the BUD documentation says outturn can carry them.
- September 2022 labels all 23,787 rows `Qtr1 - 21-22` although the months are April to June 2022;
  quarters must be derived from Month, never read from the file.

## 4. Grain

[`inyear_grain.csv`](data/inyear_grain.csv) tests seven candidate keys in every release (**tested**):

| Key | Duplicate groups (all 31 releases) |
|---|---|
| sub-segment, economic category, month | 0 |
| organisation, sub-segment, economic category, month | 0 |
| organisation, sub-segment, economic category, control budget detail, month (the plan's grain) | 0 |
| ... + economic budget (the key asked about) | 0 |
| ... + control budget code, + PESA group, every non-amount column | 0 |

There are no duplicates at all, so the question of exact repeats versus lines to be summed does
not arise. The smallest key unique in every release is (sub-segment code, economic category code,
month): within a release a sub-segment belongs to one organisation and one control budget detail.

## 5. Restatement within a financial year

Releases of the same financial year re-report every earlier month.
[`inyear_restatement_pairs.csv`](data/inyear_restatement_pairs.csv) compares each release with the
previous release of the same year over the months both hold, on the plan's key;
[`inyear_restatement_by_month.csv`](data/inyear_restatement_by_month.csv) splits that by month and
[`inyear_restatement_examples.csv`](data/inyear_restatement_examples.csv) gives the three largest
moves per pair (**tested**).

- Over the 22 release pairs, 789,645 key-months are unchanged, 50,132 change amount (5.4% of the
  keys compared), 42,676 vanish and 48,780 appear. Most vanishing keys are zero rows of the dense
  grids (question 6): 17,257 in December 2019 to March 2020 and 7,945 in September to December 2022.
- Net movement of already-reported months is between -2.7% and +9.5% of the earlier release's
  total; it is under 2% either way in 19 of 22 pairs. The +9.5% is September to December 2020,
  when HMRC filled in its COVID-19 AME subsidy line (sub-segment X041A094, subsidies to the private
  sector) for April to June 2020.
- Gross movement is distorted by unit errors at source. Two releases carry NHS Pension Scheme
  non-budget lines 1,000 times too large, offset by an equal and opposite line, which the next
  release corrects: sub-segment X903A002, April 2023, 4,100,000,000 in September 2023 then
  4,100,000 in December 2023; April 2025, 6,308,755,813 in December 2025 then 6,308,756 in March
  2026. The net movement of those two pairs is -2.0% and +0.1%, but their gross movement is
  £8.6tn and £12.6tn.

Three ordinary examples:

| Organisation | Line | Month | Before | After |
|---|---|---|---|---|
| HMR041 (HMRC) | X041A094, C101 | May 2020 | 1 (Sep 2020) | 18,463,194 (Dec 2020) |
| HMT087 (HM Treasury) | X087A004, P201 | Jun 2024 | -3,049,000 (Sep 2024) | 356,650,534 (Dec 2024), back to -3,049,000 (Mar 2025) |
| DOH033 (DHSC) | X0331002, F102 | Jun 2021 | -1,530,749 (Sep 2021) | -510,622 (Dec 2021), spread over April to June |

Delta row count ([`inyear_delta_rowcount.csv`](data/inyear_delta_rowcount.csv)): a delta row is
needed for a first appearance, a changed amount, and a key that vanishes (to reverse it). Over all
31 releases the stacked files hold 1,547,078 rows; the delta fact needs 800,109 rows, or 649,475
(42% of stacked) if zero deltas are not stored. The first release of each year is all first
appearances; later releases add 17,899 to 29,006 non-zero delta rows each.

## 6. Zero rows

[`inyear_zero_rows.csv`](data/inyear_zero_rows.csv) (**tested**): 218,092 rows are exactly zero.
Ten releases, December 2019 and September 2020 to September 2022, are dense grids: every line key
has a row for every month (grid density 1.0000) and 33% to 40% of rows are zero. The other releases
hold almost no zeros (at most 0.19%). A zero row and a missing row mean the same thing, so I would
drop zero rows before computing deltas: the invariant (sum of deltas up to a release = file total)
still holds because zero contributes nothing, and the zero-only key-months that the dense releases
add would otherwise show up as 7,000 to 17,000 spurious vanishing keys when the next release is
sparse.

## 7. Signs

[`inyear_sign_by_category.csv`](data/inyear_sign_by_category.csv) counts positive, negative and
zero rows and sums by PESA economic group and economic category, on the last release of each
financial year so that no month is counted twice (**tested**).

- Sign per row does not classify a line: 125 of 128 category codes carry both signs, and 91 have
  more than 5% of their gross value on the minority side (corrections, reversals and repayments).
- The category code does: in 116 of the 125 categories with a code, a final digit `1` has net
  positive and a final digit `2` net negative (for example `B101` purchase / `B102` sales,
  `H301` lending / `H302` repayment, `S301` interest payable / `S302` receivable). The nine
  exceptions are listed in the CSV (R101 loan write-offs, L201 discount unwinding and others).

## 8. Chart of accounts

[`inyear_account_map.csv`](data/inyear_account_map.csv) lists every (economic category code, name,
PESA group, economic budget) with first and last release (**tested**). After ignoring case and
punctuation, no category code changes its name, PESA group or economic budget across the 31
releases, except the `NA` category (`OTHER NON-BUDGET` then `NA`, see question 2). The 254 rows are
128 codes; the extra rows are case changes and the PESA group long name that only `v2019` carries.

## 9. Control budget

After removing the `TOTAL ` prefix every row is DEL, AME or NON-BUDGET; the detail code splits DEL
into DEL ADMIN and DEL PROG and AME into DEPT AME and NON-DEPT AME, and is identical across all 31
releases. Nothing fails to map (**tested**, `normalised_value` in the domain CSV and the zero
`amount_cb_other` column).

## Decisions this supports

- **GO** on the delta grain: (organisation, sub-segment, economic category, control budget detail,
  month) is unique in all 31 releases (0 duplicate groups); even (sub-segment, economic category,
  month) is.
- **GO** on a twelve-month calendar for in-year data, with one exception to handle: no period 13,
  14 or adjustment month in any release and no month outside a release's own year, but June 2019
  has 71 rows in `Period 0 - 18-19` (£269.9m).
- **GO** on each release being exactly one Version and the financial year to date: 31 of 31
  releases match the expected window.
- **GO** on revision deltas being smaller than snapshots: 649,475 non-zero delta rows against
  1,547,078 stacked rows (42%).
- **GO** on Decimal-exact control totals: 32 files, exact sums; rounding to four places moves a
  file total by at most £5.44.
- **NO-GO** on trusting Quarter: September 2022 mislabels all 23,787 rows.
- **NO-GO** on sign as an income/expenditure flag: 125 of 128 categories carry both signs; use the
  code's final digit (116 of 125 consistent) or an authored map.

## What I would change in the design

- Drop zero rows before computing deltas (ten releases are zero-filled grids; 218,092 zero rows).
- Give the calendar a period 0 member (or route the 71 June 2019 rows to an "annual adjustment"
  member) rather than assume Apr-Mar only; the plan's Time Intelligence group already mentions
  period 13, which in-year data never uses.
- Load both `amount_sum` and the four-decimal sum into the audit table, and test the warehouse
  against the rounded one; consider `DECIMAL(19,6)` if exact parity with the file is preferred,
  since 14,959 amounts have more than four decimals.
- Add a data-quality check for unit errors: lines whose absolute amount exceeds, say, £1bn and
  that change by a factor near 1,000 between releases (two cases found, both NHS Pension Scheme
  non-budget). They do not break totals but they wreck any gross-movement measure.
- Treat economic budget as an attribute of the economic category, not part of the key: it is
  determined by the category, and its `NA`/`OTHER NON-BUDGET` relabel in December 2022 would
  otherwise appear as a vanish-and-appear pair in the deltas.
