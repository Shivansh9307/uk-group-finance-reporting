# Data dictionary: OSCAR in-year, raw and staging

What `ukfr build --scope committed` puts in the database from the 31 in-year releases (March 2019 to
September 2026) that are committed under `data/committed/oscar_inyear/`. Row counts below come from
`evidence/build/table_counts.csv`, which the build writes (**tested**: `pipeline/tests/test_audit_output.py`
compares it with a fresh export). Amounts are GBP thousands, spending positive, income negative.

Everything on this page is from the real releases. There is no synthetic or authored data in these
tables.

## Tables

| Table | Rows | Grain | Key |
|---|---|---|---|
| `raw.oscar_inyear` | 1,547,078 | one data row of a primary file | (`file_id`, `source_row`) |
| `raw.oscar_inyear_file` | 32 | one data file in the manifest | `file_id` |
| `raw.oscar_inyear_control_expected` | 32 | one data file in the control CSV | (`release`, `filename`) |
| `quarantine.oscar_inyear` | 0 | one rejected row | (`file_id`, `source_row`) |
| `stg.inyear_snapshot` | 1,328,986 | release x organisation x sub-segment x economic category x control budget detail x period | the grain, see below |
| `stg.release` | 31 | one release | `release` |
| `audit.file_control` | 32 | one data file | `file_id` |
| `audit.table_counts` | 6 | one table outside `audit` | (`schema_name`, `table_name`) |

`raw.oscar_inyear` holds 1,547,078 rows because that is the sum of `data_rows` over the 31 primary
files in `data/audit/inyear_file_control_totals.csv`; `stg.inyear_snapshot` holds 218,092 fewer, the
exact-zero rows (**tested**: `sql/tests/005_staged_rows_equal_nonzero_rows.sql`).

## raw.oscar_inyear

The reader's canonical columns as text exactly as read (spaces around a field stripped, line breaks
inside quoted fields kept as one record), with the amount also stored exactly. No type conversion, no
row dropped except fully blank rows (counted in `raw.oscar_inyear_file`).

| Column | Type | Meaning |
|---|---|---|
| `file_id` | int | which file, `raw.oscar_inyear_file` |
| `source_row` | int | row number in the source, header = 1, blank rows counted; lineage back to the file |
| `release` | varchar(7) | `2019-03` ... `2026-09` |
| `organisation_code` ... `month` | nvarchar | the 16 canonical text columns (`organisation_name`, `control_budget_code`, `control_budget_detail_code`, `department_name`, `sub_segment_code`, `sub_segment_name`, `economic_category_code`, `economic_category_name`, `economic_budget_code`, `pesa_economic_group_code`, `pesa_economic_group_name` (empty outside the 2019 layout), `version`, `year`, `quarter`, `month`) |
| `amount_text` | nvarchar(100) | the Amount as written: `"2,394"`, `1.13687E-13`, `-8.33E-05` |
| `amount_whole` | bigint | integer part of the exact amount, toward zero |
| `amount_frac` | decimal(38,31) | the rest, same sign; `amount = amount_whole + amount_frac` with no rounding |

Why two columns: the 2026-03 release carries amounts with up to 31 decimal places next to values of up
to ten digits (largest absolute amount 6,310,103,398), which no single `DECIMAL(38,s)` holds exactly,
and the exact file total in the control table has 40 significant digits. Summing the two columns and
rendering the pair with `audit.exact_sum_text` reproduces every control total digit for digit
(**tested**: `sql/tests/003_raw_exact_sum_equals_file_sum.sql`, all 31 releases, and
`pipeline/tests/test_audit_output.py` for the function's sign and carry cases). The storage is
columnstore (`cci_raw_oscar_inyear`).

## raw.oscar_inyear_file

One row per data file, including the one that is not loaded.

| Column | Meaning |
|---|---|
| `file_id` | 1..32 in (release, file name) order |
| `release`, `filename`, `member`, `container` | from `data/manifest/files.csv`; `member` is the zip member, `container` is `zip-csv`, `zip-ods`, `csv` or `ods` |
| `primary_for_release` | `Y` for the file that is loaded; from the control CSV, and a release must have exactly one |
| `first_published` | as written in the manifest; the release date |
| `sha256_manifest`, `sha256_file` | the recorded hash, and the hash of the file at load time |
| `header_variant`, `sheet` | `v2019`, `v2021sep`, `v2021dec`, `v2023`; the ODS sheet that held the data |
| `total_rows`, `blank_rows`, `data_rows` | rows after the header, blank ones, and the rest (the rows read) |
| `load_status` | `loaded`, or `duplicate_of_primary` |
| `duplicate_of_file_id`, `duplicate_identical`, `content_digest` | the twin proof, see below |

March 2026 is published twice, as a zip holding an ODS (the primary) and as a bare ODS. The loader
reads both through the same reader and compares an order-independent digest of every row (all 16
canonical text columns and the exact amount) and the row count. They are identical (53,604 rows,
`duplicate_identical = 1`), and the bare file has no rows in `raw`, `quarantine` or `stg`
(**tested**: `sql/tests/008_twin_identical_not_loaded.sql`).

## quarantine.oscar_inyear

The columns of `raw.oscar_inyear` with the amount left as text, plus `reason_code` and
`reason_detail`. A row is rejected, never dropped, for exactly one of these reasons:

| `reason_code` | When |
|---|---|
| `amount_unparseable` | the Amount is not a number the reader can read exactly |
| `amount_blank` | the Amount is empty |
| `amount_scale` | more than 31 decimal places |
| `amount_range` | an integer part of 18 digits or more |
| `month_unrecognised` | Month is neither a calendar label (`Apr-22`) nor `Period 0 - yy-yy` |

The 31 real releases have no rejects (**tested**: `sql/tests/009_nothing_quarantined.sql`). The
mechanism is shown with planted bad rows in a scratch table, through both the bulk and the
`executemany` loaders (**tested**: `pipeline/tests/test_stage_oscar_inyear.py`, `test_planted_bad_rows_land_in_quarantine_with_their_reason`).
An unknown header still stops the build for the whole file.

## stg.inyear_snapshot

Typed rows, zero-amount rows dropped. `financial_year` and `period` come from the Month text, never
from Year or Quarter.

| Column | Type | Meaning |
|---|---|---|
| `release` | varchar(7) | |
| `organisation_code`, `sub_segment_code`, `economic_category_code`, `control_budget_detail_code` | nvarchar | source codes, unchanged |
| `period` | tinyint | 1 = April ... 12 = March; 0 = not allocated to a month |
| `financial_year` | varchar(7) | `2022-23` |
| `fiscal_quarter` | tinyint | `(period + 2) / 3`; NULL for period 0 |
| `control_budget_code`, `economic_budget_code`, `pesa_economic_group_code` | nvarchar | as published (`TOTAL DEL` from December 2022) |
| `amount` | decimal(19,4) | the exact amount rounded half away from zero |
| `file_id`, `source_row` | int | lineage to `raw.oscar_inyear` |

Grain: (`release`, `organisation_code`, `sub_segment_code`, `economic_category_code`,
`control_budget_detail_code`, `period`) is the clustered primary key and is unique in all 31 releases
(**tested**: `sql/tests/006_grain_unique.sql`). Release is part of the key because every release
restates the year to date.

Period 0 is the 71 June 2019 rows labelled `Period 0 - 18-19`: they stay as period 0 of FY2018-19
(not allocated to a month), in year totals and year to date, and appear in no other release
(**tested**: `sql/tests/011_period_zero_is_june_2019_only.sql`). September 2022 labels every row
`Qtr1 - 21-22`; the staged quarter is derived from the month and the Quarter column is not kept
(**tested**: `sql/tests/012_quarter_from_month.sql`).

Each release covers exactly its expected year to date: a March release periods 1-9 and a June release
1-12 of the financial year that began the year before, a September release 1-3 and a December release
1-6 of the financial year that began that year (**tested**: `sql/tests/007_release_window.sql`, written
against a rule that does not use the load).

A note for the next task: 218,092 exact-zero rows are dropped, but some amounts are float residue such
as `-1.06581E-14`. They are not zero, so they stay, and many round to `0.0000` at four decimals.
`audit.file_control.rounds_to_zero_rows` counts them per release (between 0 and 15 per release, 58 in
total in the real releases). A delta calculation that wants "zero equals absent" has to treat an amount
of `0.0000` the same way.

## stg.release

| Column | Meaning |
|---|---|
| `release`, `release_seq` | label, and 1..31 in publication order (first published, then label) |
| `financial_year` | the financial year the release reports on (periods 1 and above) |
| `first_published` | date part of the manifest's `first_published` |
| `highest_period` | 3, 6, 9 or 12 |
| `version_label` | the one `Version` value the release carries (**tested**: exactly one per release, `sql/tests/013_release_table.sql`) |
| `file_id` | the loaded file |

## audit.file_control

One row per data file, loaded figures beside expected ones from `data/audit/inyear_file_control_totals.csv`,
with `pass`, `fail` or `not loaded` per measure and an `overall_status`. Written to
`evidence/build/file_control.csv`. The measures:

| Measure | Compared |
|---|---|
| sha256 | hash at load, manifest, control CSV |
| rows | rows read = rows loaded + rows quarantined = expected `data_rows` |
| zero rows | exact-zero rows in `raw` = expected `zero_rows` |
| exact sum | `audit.exact_sum_text(SUM(amount_whole), SUM(amount_frac))` = expected `amount_sum`, as text |
| staged rows | `stg` rows = `data_rows` - `zero_rows` |
| staged sum | `SUM(amount)` in `stg` = `amount_sum_rounded_4dp` |
| twin | for a file that is not loaded: identical to the primary, no rows loaded |

All 32 files pass (**tested**: `sql/tests/016_file_control_all_pass.sql`). Rounding each amount to four
places moves a file total by up to GBP 5.44 (2024-06), which is why the staged sum is compared with the
rounded control total and the raw sum with the exact one; both are in the table.

## Independent control

`data/audit/inyear_independent_control.csv` recomputes each file's row count, zero-row count and
amount sum with code that shares nothing with the readers: the `csv` module over each zip member for
CSV releases and `python-calamine` for the ODS (`ukfr control inyear`, about 12 s). The control CSV the
loader checks against was produced by the loader's own reader, so this is the only tie to source that
does not depend on it (**tested**: `pipeline/tests/test_independent_control.py`).

- CSV releases (30 of 31 primary files): row count, zero rows, exact sum and four-decimal sum agree
  exactly with the loaded data.
- The one ODS release (2026-03, both copies): row count agrees exactly. Calamine returns binary floats,
  so the sums agree only within a tolerance I set after seeing the difference: exact sum within
  1e-6 and four-decimal sum within 0.01, against observed differences of about 9e-10 and 0.0028. The
  tolerance is a limit of the independent method, not of the load; the load's own exact sum is
  digit for digit equal to the control table.

## Not in this layer

No dimensions, no revision deltas, no organisation keys: those start from `stg.inyear_snapshot` in
later tasks. Department and organisation names are in `raw` only, for the same reason.
