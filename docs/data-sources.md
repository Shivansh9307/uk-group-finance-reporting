# Data sources

Every number in the model has to tie back to a published file. This page lists the files I use,
how I find and download them, and what I found odd about them. The machine-readable versions are
[`data/manifest/sources.yml`](../data/manifest/sources.yml) (what to fetch) and
[`data/manifest/files.csv`](../data/manifest/files.csv) (what was found: one row per file, with
URL, size and sha256).

Statements are labelled **tested** (I ran it; the command and result file are given) or
**designed** (built that way, not yet exercised end to end). Facts about the files themselves were
observed on 2026-11-16, when I ran the fetch.

## Sources

All sources are published under the Open Government Licence v3.0 (see
[DATA_LICENCES.md](../DATA_LICENCES.md)).

| Source id | What | Publisher | Where it is published | Format | What I use it for |
|---|---|---|---|---|---|
| `oscar_inyear` | OSCAR II in-year releases, quarterly, March 2019 to September 2026 (31 releases) | HM Treasury | [HMT OSCAR collection](https://www.gov.uk/government/collections/hmt-oscar-publishing-from-the-database), "In-year data" | zip holding one CSV; September 2026 a bare CSV; March 2026 a zip holding an ODS | Outturn by organisation, segment and account, as reported in each quarterly snapshot |
| `oscar_annual_bud` | OSCAR annual releases November 2023, 2024 and 2025 (five years each) plus the "Understanding OSCAR" notes and the Period/Version relationship workbook | HM Treasury | Annual release pages in the same collection | xlsx (9 to 15 MB each), pdf, docx | Restated annual outturn on the current structure; how periods and versions relate |
| `oscar_annual_extract` | November 2022 annual extracts, 2017-18 to 2021-22; the November 2019 to 2021 extracts are listed only | HM Treasury | [November 2022 annual release](https://www.gov.uk/government/publications/oscar-annual-release-november-2022) | zip holding one pipe-delimited txt of about 3 GB | Plans to FY2021-22 and departments' monthly forecast returns for FY2017-18 to FY2020-21 |
| `oscar_mfo` | Monthly forecast and outturn (MFO) files for FY2021-22 and FY2022-23 | HM Treasury | November 2022 and November 2023 annual release pages | zip holding one CSV per return | Departments' own monthly forecasts for the backtest |
| `estimates_del` | "Departmental DEL budgets: tables" from Main and Supplementary Estimates, FY2022-23 to FY2026-27 | HM Treasury | [Main Estimates](https://www.gov.uk/government/collections/hmt-main-estimates) and [Supplementary Estimates](https://www.gov.uk/government/collections/hmt-supplementary-estimates) collections | xlsx | Plan at department group x resource/capital DEL from FY2022-23 |
| `pesa` | PESA Chapter 1 tables 2022 to 2026, the PESA 2025 December update, and the Spending Review 2025 DEL tables | HM Treasury | [PESA collection](https://www.gov.uk/government/collections/public-expenditure-statistical-analyses-pesa); [SR25 supporting documents](https://www.gov.uk/government/publications/supporting-documents-for-spending-review-2025) | xlsx | AME and admin plans where they exist; Spending Review group names |
| `pss` | Public Spending Statistics July 2026: database and Chapter 1 | HM Treasury | [PSS July 2026](https://www.gov.uk/government/statistics/public-spending-statistics-release-july-2026) | xlsx | Independent outturn cross-check on the data controls page |
| `gdp_deflator` | GDP deflators at market prices, latest three releases (October 2026 Budget, September 2026 QNA, June 2026 QNA) | HM Treasury | [GDP deflators collection](https://www.gov.uk/government/collections/gdp-deflators-at-market-prices-and-money-gdp) | xlsx | Real-terms restatement; three vintages to show the base-year shift |
| `tac` | NHS trust accounts consolidation (TAC) data, FY2019-20 to FY2024-25: one data workbook for NHS trusts and one for NHS foundation trusts each year, plus the illustrative form of each year | NHS England | [TAC data publications](https://www.england.nhs.uk/financial-accounting-and-reporting/nhs-providers-tac-data-publications/); the FY2019-20 files are on three publication pages linked from it | xlsx (17 to 39 MB each) | Statutory income statement, balance sheet and cash flow by NHS provider; the illustrative forms give the line text and sign |
| `ons_cpi` | CPI index (D7BT) and CPI annual rate (D7G7) | Office for National Statistics | [D7BT](https://www.ons.gov.uk/economy/inflationandpriceindices/timeseries/d7bt/mm23), [D7G7](https://www.ons.gov.uk/economy/inflationandpriceindices/timeseries/d7g7/mm23) | CSV generated on request | Price index for real-terms comparisons |

The NHS trust accounts (TAC) files are registered below. Departmental workforce files are fetched later
with the same tool and are not registered yet.

## How discovery works

HM Treasury file URLs contain an asset hash that cannot be guessed, and pages are re-issued with
new files, so I never hard-code a gov.uk file URL. Each source in `sources.yml` names where to
look, and the fetcher asks the [gov.uk Content API](https://content-api.publishing.service.gov.uk/)
what is there (**tested**, see below):

- `page`: one publication page; its `details.attachments[]` are enumerated. HTML attachments
  (guidance published as a web page) have no file name and are recorded as `<slug>.html`.
- `collection`: a collection page; `links.documents` are filtered by collection group, path regex,
  title regex, a release window (`since`/`until`) or "latest N", and each page is then enumerated.
- `url`: a fixed URL, for files that are not attachments (the ONS CSV generator).
- `html_index`: links scraped from any HTML page by regex. This is for the NHS England TAC index,
  which is not on gov.uk (**tested**: a fixture page in `pipeline/tests/test_discover.py`, and the
  real page: `ukfr fetch --source tac` found and downloaded 18 files on 2026-11-24, results in
  `data/manifest/files.csv`). The FY2019-20 files are not on the index page itself but on three publication pages, so
  `tac` has four `html_index` entries.

Every file gets a release label from a regex over the page title, path or file name (for example
`2026-09` for the September 2026 in-year release, `2025-26-supps`, `2026-10-budget`). The first
matching file rule then decides whether the file is fetched, listed as catalogue-only, or ignored.
Within one release, rules can be tiered: for OSCAR in-year I take the zip or CSV and list the ODS
and xlsm copies as catalogue-only, unless the zip holds no CSV, in which case the ODS is fetched as
well (that happened for March 2026). The publication dates in the manifest are the page's
`first_published_at` and `public_updated_at` from the API.

The fetcher sends a generic User-Agent, waits one second between requests, retries 429 and 5xx
responses with exponential backoff (honouring `Retry-After`), streams downloads to a `.part`
file and renames it only when complete.

## Running it

From the repository root, with [uv](https://docs.astral.sh/uv/):

```
uv run --project pipeline ukfr fetch                       # everything
uv run --project pipeline ukfr fetch --source pss          # one source (repeatable)
uv run --project pipeline ukfr fetch --catalogue-only      # discover and list, no downloads
uv run --project pipeline ukfr fetch --verify              # offline sha256 check
```

Large files go to `$UKFR_DATA_DIR/<source id>/<release>/`. If `UKFR_DATA_DIR` is not set, that is
`data/raw/`, which git ignores. The manifest records those files as `$UKFR_DATA_DIR/...` so it holds
no machine-specific path.

- **Resume** (**tested**: `test_rerun_resumes_without_downloading_again`): a rerun skips any file
  whose bytes on disk already match the recorded sha256. My second full run on 2026-11-16
  downloaded only the two ONS CSVs and otherwise made HEAD and Content API requests.
- **Changed at source** (**tested**: `test_changed_file_at_source_fails_loudly`): if a file
  downloads with a different sha256 from the one in the manifest, the run fails, keeps the recorded
  version, and names the file. `--accept-changes` takes the new version.
- **Dead links** (**tested**: `test_dead_link_is_recorded_not_raised`): a 404 or 410 is recorded
  with `fetched = dead` in `files.csv` and in
  [`data/manifest/dead_links.csv`](../data/manifest/dead_links.csv) with the page that links to
  it; the run carries on.
- **Verify** (**tested**): `--verify` makes no network calls. It recomputes the sha256 of every
  file marked fetched: committed files must be present and match; raw files are checked if
  `$UKFR_DATA_DIR` has them and otherwise counted as "not present locally" without failing. A file
  under `data/committed/` that the manifest does not list is also a failure. The result on
  2026-11-16 is in [`evidence/fetch/verify.txt`](../evidence/fetch/verify.txt).
- **Volatile sources**: the ONS generator rebuilds its CSV on every request, so `ons_cpi` is marked
  `volatile: true`. It is downloaded again on every run, and a changed sha256 is a warning in both
  `fetch` and `--verify`, not a failure (**tested**: `test_volatile_source_mismatch_is_a_warning`).
  The manifest takes its date from the file's own "Release date" line.

Tests: `uv run --project pipeline pytest -q` (32 passed on 2026-11-16, output in
[`evidence/fetch/pytest.txt`](../evidence/fetch/pytest.txt)). They use hand-trimmed Content API
responses in `pipeline/tests/fixtures/` served through a mock transport, so they make no network
calls.

## Committed versus fetched

Three sources are kept in git, 48 files and 28.7 MB in all (`commit: true` in `sources.yml`):

| Source | Files | Size | Why it is in git |
|---|---|---|---|
| `oscar_inyear` | 32 (31 releases, plus the March 2026 ODS) | 27.6 MB | the core outturn fact |
| `estimates_del` | 9 workbooks, FY2022-23 to FY2026-27 | 0.30 MB | the plans from FY2022-23, small enough to commit |
| `pesa` | 7 workbooks (PESA 2022 to 2026, the December 2025 update, the Spending Review 2025 DEL tables) | 0.81 MB | departmental AME and administration plans |

With them in the repository anyone can clone it and rebuild the model's main tables, and CI can
rebuild the database without downloading anything. I set a 60 MB cap in `sources.yml`; the fetcher
stops before downloading if the committed set would exceed it. Everything else is downloaded by the
fetcher into `$UKFR_DATA_DIR` (620 MB, from the manifest): the annual BUD workbooks (177.7 MB), the
annual extracts (283.9 MB), the MFO files (155.8 MB), the Public Spending Statistics workbooks
(2.7 MB, `commit: false`) and the deflators and ONS series. The manifest's sha256 proves the downloaded
copy is the one I used. **Tested**: `uv run --project pipeline ukfr fetch --verify` checks all 48
committed files and every raw file that is present.

`.gitattributes` marks `data/committed/**` as binary so git never rewrites line endings: the
September 2026 CSV uses CRLF, and a converted copy would no longer match its sha256.

## Dead links and what they cost

| File | Page | Status |
|---|---|---|
| `MFO_23-24.zip` (listed as 438.7 MB) | [OSCAR annual release November 2024](https://www.gov.uk/government/publications/oscar-annual-release-november-2024) | 404 |
| `MFO_24-25.zip` (listed as 469.1 MB) | [OSCAR annual release November 2025](https://www.gov.uk/government/publications/oscar-annual-release-november-2025) | 404 |

Both pages still list these files with a size, but the asset server returns 404 for them
(**tested**: the 2026-11-16 fetch, `data/manifest/dead_links.csv`). They are the only source of
departments' own monthly forecast returns after FY2022-23, so the forecast backtest stops at
FY2022-23. It covers six years, FY2017-18 to FY2022-23: the annual extracts hold a complete set of
monthly returns for FY2017-18 to FY2020-21 (**tested**: `docs/profiling/oscar-annual-extracts.md`),
and the MFO files cover the last two.

## File quirks I observed

- **March 2026 in-year zip** holds `OSCAR_in_year_dataset_March_2026.ods`, not a CSV. The ODS
  attached separately to the page is a different size (3,049,596 bytes against 3,050,298 inside the
  zip), so I keep both.
- **September 2026** is published as a bare CSV (4,807,557 bytes) and an xlsm, with no zip. The
  CSV is not UTF-8: it contains bytes 0x96 (en dash) and 0xA0 (no-break space), which fits
  Windows-1252. Lines end in CRLF.
- **In-year zip member names drift**: December 2019's member is
  `191209 DataSet3+Monthly+in-year+data+for+current+year.csv`; June 2024's zip is called just
  `OSCAR_in-year_dataset.zip`.
- **The four larger November 2022 extracts use Deflate64** (zip method 9), which Python's
  `zipfile` cannot read. Each holds one pipe-delimited, fully quoted txt with 91 columns and 2.9 to
  3.2 GB uncompressed. The 2021-22 extract is standard deflate (278 MB uncompressed). I read them
  as streams with `ukfr.zipstream`, which reads the zip directory with the standard library and
  decompresses with `inflate64` 1.0.4; nothing is extracted to disk (**tested**: `ukfr zip-head`
  read the first 1,000 lines of the 2017-18 extract in about 3 seconds including start-up,
  [`evidence/fetch/deflate64_head.txt`](../evidence/fetch/deflate64_head.txt)). I did not need
  7-Zip, which is not installed on my machine. `AMOUNT` values are
  zero-padded text with a leading space and a trailing point, such as `" 000000000005000."`.
- **MFO zips** hold one CSV per return: R01 to R13 for FY2021-22, R00 to R13 for FY2022-23. One
  member breaks the naming pattern: `MFO-R09-202223.csv`.
- **November 2023 annual release** sits at a path with no date in it
  (`/government/publications/oscar-ii-publishing-raw-data-from-the-database`), and its MFO file was
  added later (`MFO_2022-23_New.zip`).
- **November 2020 extracts** are reported by the Content API with content type `invalid/invalid`,
  although the asset server serves them as `application/zip`.
- **September 2021 in-year page** reports `public_updated_at` of 21 December 2021, the same moment
  as the December 2021 release, so `public_updated_at` is not a reliable release date;
  `first_published_at` is.
- **Estimates**: Main Estimates 2024-25 has no DEL tables workbook (PDF only), so that year uses the
  Supplementary Estimates; `sources.yml` records this as a known gap rather than an error. For
  2022-23 there are three workbooks: Main Estimates, the Out-of-Turn Supplementary Estimates
  (`Main_Estimates_DEL_tables_OUTOFTURN_Updated.xlsx`, a page of its own, attachment titled
  "Departmental DEL budgets" without ": tables"), and the Supplementary Estimates.
- **PESA 2026 Chapter 1**: I had a note that this file held Chapter 10 tables at source. The copy I
  downloaded on 2026-11-16 (`PESA_2026_CP_Chapter_1_tables.xlsx`, 119,498 bytes) has sheets
  `Table_1_1` to `Table_1_14` headed "Table 1.1 Total Managed Expenditure, 2021-22 to 2028-29" and
  so on, so it is the Chapter 1 file. The manifest note records this.
- **PESA 2025 December update** is attached to the PESA 2025 page, so it shares the `2025` release
  folder with the July Chapter 1 file.
