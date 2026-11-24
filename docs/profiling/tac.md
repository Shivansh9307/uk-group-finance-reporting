# Profile: NHS trust accounts consolidation (TAC) data

What the TAC files are, what is in them and what I decided before building anything. Every claim is
labelled **tested** (the command and the result file are named) or **designed** (not run). I profiled on
2026-11-24. The numbers come from `uv run --project pipeline ukfr profile tac` (about 6 minutes; it reads
the 12 data workbooks through the loader's reader) and from `uv run --project pipeline ukfr control tac`
(about 2 minutes; `python-calamine`, no shared code), whose results are the CSV files under
`docs/profiling/data/tac_*.csv` and `data/audit/tac_independent_control.csv`.

## 1. Where the files are

- NHS England publishes the trust accounts consolidation (TAC) data on one page,
  `england.nhs.uk/financial-accounting-and-reporting/nhs-providers-tac-data-publications/`, not on gov.uk.
  Licence: Open Government Licence v3.0 (the page footer). **Tested**: `ukfr fetch --source tac` found and
  downloaded 18 files with no error (`data/manifest/files.csv`, source `tac`).
- Six financial years are there, FY2019-20 to FY2024-25. For each year there is one workbook for NHS trusts,
  one for NHS foundation trusts and one illustrative form (the form with no data). That is 12 data files and 6
  forms. FY2024-25 is the latest; FY2017-18 and FY2018-19 sit in the National Archives copy of the
  NHS Improvement site and were not fetched.
- The FY2019-20 files are not on the index page. They are linked from three publication pages, so the manifest
  entry has four `html_index` discoveries. A file name has no fixed pattern (`...-trust-accounts-for-2020-21`
  singular in one year, `202223-NHS-Provider-TAC-Illustrative-File.xlsx` with no hyphen in another), so the
  release label is read from the name by a regex per page. **Tested**:
  `pipeline/tests/test_tac.py::test_every_tac_file_in_the_manifest_gets_its_release_from_a_discovery_rule`
  checks that all 18 names get the folder's release label.
- The files are 17 to 39 MB and are kept out of git (`$UKFR_DATA_DIR/tac/<year>/`); their sha256 is in the
  manifest, `ukfr fetch --verify` checks them.

## 2. What is in a data workbook

Five sheets, the same in every year: `Intro` (text), `List of providers`, `All data`, and two pivot sheets that
are formulas over `All data` (not read). The 2023-24 files also hold a hidden check sheet. **Tested**:
`docs/profiling/data/tac_files.csv`.

`All data` is a long table with one header row and seven columns:

| Column | Example | Meaning |
|---|---|---|
| organisation name | `Barts Health NHS Trust` | the provider, as text only: the sheet has no code |
| worksheet name | `TAC03 SoFP` | the form the value belongs to |
| table id | `1` | a block of the form (the income statement has two) |
| main code | `A03CY01` | `A`, sheet 03, `CY` current year or `PY` prior year, column 01 |
| row number | `44` | the row in the TAC form |
| sub code | `BAL1400` | the line: this is the line key |
| total / value number | `130344` | thousands of pounds |

The header text changes: 2019-20 to 2021-22 write `Organisation Name` and `Value number`, 2022-23 onwards
`OrganisationName` and `Total`. The reader compares headers with spaces removed and stops on any other
header (**tested**: `pipeline/tests/test_tac_reader.py`).

The code carries no descriptions. The line text and the sign the form expects (`+`, `-`, `+/-`) are in the
illustrative form of the same year (sheets `TAC02 SoCI`, `TAC03 SoFP`, `TAC05 SoCF`). The provider's NHS (ODS)
code is only in `List of providers`, joined to the data by name.

### Sizes

`All data` has 28 worksheets (29 in 2022-23, which adds `TAC14A RoU Assets`): the three statements and 25
note forms (operating income, staff costs, property plant and equipment, leases, pensions and so on).
I load only the three statements, which are what the model needs; the other worksheets are counted in
`raw.tac_worksheet` and their rows are checked by the independent control, so what is left out is known.

| Year | Trust file: rows in `All data` | Statement rows | Foundation trust file: rows | Statement rows | Listed providers (trust + foundation) | With statements |
|---|---|---|---|---|---|---|
| 2019-20 | 458,888 | 20,064 | 888,338 | 39,336 | 77 + 149 | 76 + 149 |
| 2020-21 | 433,313 | 18,744 | 891,256 | 39,072 | 71 + 148 | 71 + 148 |
| 2021-22 | 432,950 | 18,480 | 884,210 | 38,280 | 70 + 145 | 70 + 145 |
| 2022-23 | 464,780 | 18,632 | 970,560 | 39,456 | 69 + 144 | 68 + 144 |
| 2023-24 | 481,140 | 18,084 | 1,006,040 | 38,360 | 68 + 143 | 66 + 140 |
| 2024-25 | 473,088 | 17,952 | 995,742 | 38,352 | 67 + 143 | 66 + 141 |

The statement rows add up to 344,812 over the six years (**tested**: `docs/profiling/data/tac_files.csv` and
the independent control agree row for row, `sql/tests/100_tac_file_control_all_pass.sql`).

## 3. Code schemes

**Stable.** The same codes carry the same lines in every year, which is the most useful fact in the files.
**Tested** (`docs/profiling/data/tac_subcode_years.csv`, `sql/tests/110_tac_every_line_has_text_sign_section_and_kind.sql`):

| Statement | Sheet | Main codes | Sub codes 2019-20 | 2022-23 | 2024-25 |
|---|---|---|---|---|---|
| Income statement (SoCI), table 1 | `TAC02 SoCI` | `A02CY01`, `A02PY01` | 27 | 27 | 26 |
| SoCI, table 2 (allocation of surplus) | same | same | 6 | 6 | 6 |
| Balance sheet (SoFP) | `TAC03 SoFP` | `A03CY01`, `A03PY01` | 39 | 40 | 40 |
| Cash flow (SoCF) | `TAC05 SoCF` | `A05CY01`, `A05PY01` | 60 | 64 | 64 |

- Sub codes are `SCI`/`SOC` (income statement), `BAL` (balance sheet) and `SCF`/`CFS` (cash flow) plus four
  digits and sometimes a letter. A sub code belongs to one statement only. Data codes equal the forms' codes
  in every year: no code in the data is missing from the form of its year and no form code is missing from
  the data.
- Changes over six years are few. IFRS 16 (leases, from 1 April 2022) added `BAL1115` (right of use assets) and
  four cash-flow lines (`SCF0216A/B/C`, `SCF0227`). `SOC0145` (a gain on transfers by absorption, in other
  comprehensive income) is on the forms to 2023-24 and not in 2024-25. Three lines kept their code and
  changed their wording (`SCF0280`, `SCF0295` for leases, `BAL1230` wording only). I record these in
  `authored/tac_code_map.csv` (4 rows). There is no case where a code was reused for a different line, so the
  cross-year map is short; I did not invent rows to make it look fuller.
- Every file has both columns for all three statements: **the prior-year column exists in every year**
  (**tested**: `sql/tests/109_tac_statement_columns_come_in_pairs.sql`). The 2019-20 file's prior year is
  2018-19, so the fact reaches back to 2018-19 for the balance sheet's opening balance.

## 4. Values

- Unit: thousands of pounds. Signs are the forms' signs (income and assets positive, expenses and liabilities
  negative; `+/-` lines either), not the OSCAR sign.
- Decimals: of 344,812 statement values, 301,549 are whole numbers and 43,263 have one to five decimal places
  (24,051 have five) (`docs/profiling/data/tac_value_decimals.csv`, **tested**). Some providers fill the form
  with pounds below the thousand. Maximum is five decimal places, so the raw landing column is `DECIMAL(38,10)`
  and the warehouse column is `DECIMAL(19,4)`; the fifth decimal is rounded away and the control tests both
  sums (see `docs/data-dictionary/tac.md`).
- Excel stores some of these as float artefacts (`-9673.779330000001`); the reader rounds to the 15 significant
  digits Excel shows, which gives `-9673.77933` (**tested**: `pipeline/tests/test_tac_reader.py`).

## 5. Providers

- The list of providers gives name, NHS (ODS) code, region and sector, a free-text comment, and for foundation
  trusts in 2019-20 to 2022-23 an authorisation date. 228 distinct NHS codes appear in the lists over the six
  years (`docs/profiling/data/tac_provider_list.csv`).
- **The code is the key, the name is not.** Names change (a trust acquires another and takes a new name) and
  the data sheet has no code, so a data row is joined to its provider by name key. The names do not always
  agree between the data and the list: a damaged apostrophe (U+FFFD in `Birmingham Women?s`), `&` against
  `and`, case. A normalised name key resolves every one (**tested**:
  `sql/tests/103_tac_nothing_quarantined_and_every_row_has_a_provider_and_a_line.sql`, no row unmapped).
- A code is never shared by two names in one year, and a name key is never shared by two codes. One body
  changed its code: Camden and Islington (TAF) became North London NHS Foundation Trust (G6V2S) in 2024-25.
- **Not every listed provider has data.** Nine provider-years are "excluded from this dataset" because the
  accounts were not adopted by publication time (Leicester in 2019-20, Birmingham Women's and Children's in
  2023-24 and 2024-25, and others) and one was acquired before the year (the comment says there is no data). I
  report these in `dw.tac_provider_year.list_status`, **tested** by
  `sql/tests/106_tac_providers_without_data_each_have_a_reason.sql` (no provider-year is left without a reason).
  An excluded provider's year is not lost: the next year's prior-year column carries it.
- **Three provider-years looked missing and were not.** In the first profile, West Hertfordshire (2021-22,
  2022-23) and South Warwickshire (2022-23) were listed with no data and no reason. The data sheets name them
  `West Hertfordshire Teaching Hospitals NHS Trust` and `South Warwickshire University NHS Foundation Trust`,
  the later names, while the list still has the earlier ones (812 statement rows between the three: 264, 274 and 274). With a
  plain name match those rows did not join and went to `quarantine.tac_unmapped_row`; I
  author the three aliases in `authored/tac_name_alias.csv`, with the evidence, and a test requires every alias to
  be needed and every data name to match a provider (`sql/tests/115_...`).
- Mergers and dissolutions are stated in the comments, mostly on the acquirer ("This provider acquired X
  (code) on 1 April 2020"). I author the 23 predecessor-to-successor links in
  `authored/tac_provider_successor.csv`, each with a fragment quoted from the source's own comment, and a
  test finds every fragment in the raw comments (`sql/tests/112_tac_successor_evidence_is_in_the_source_comment.sql`).
  One successor is an integrated care board (QUA), which is not a TAC provider.
- There is no OSCAR organisation per trust. The group link is at department level, to the Department of
  Health and Social Care.

## 6. The statements are consistent

- **Balance sheet.** Total assets employed (`BAL1400`) equals total taxpayers' and others' equity
  (`BAL1500`) for every provider, year and column to within £1,000: of the 2,568 pairs, 696 are equal and
  1,872 differ by less than 1 in £000 (the largest is 0.9474, that is £947; the rounding above); none differs by 1 or more
  (`audit.tac_sofp_balance`, **tested** by `sql/tests/107_tac_sofp_balances_and_every_pair_is_listed.sql`).
  I checked the same on the profile's copy of the data before building.
- **Grain.** The key (provider, file, worksheet, table, main code, sub code) has no duplicate in any file.

## 7. Decisions this supports

1. Six years, two files each, is enough: build FY2019-20 to FY2024-25 (the brief's floor is three).
2. Key a provider on the NHS code; join the data to the list by a normalised name key; report any row that
   cannot be joined (there are none).
3. Load `TAC02`, `TAC03` and `TAC05` into `raw`, count every other worksheet and check the counts. The note
   worksheets can be added later by changing one constant in the reader; that is **designed**, not tested.
4. Keep both CY and PY columns: the balance sheet's PY column is the opening balance, and PY of year Y against
   CY of year Y-1 is a control (restatements are real).
5. Line text and sign come from the illustrative forms; sections and the line/subtotal/total split are
   authored (`authored/tac_line_role.csv`) and labelled as such.
6. Store `DECIMAL(19,4)` in the warehouse, exact `DECIMAL(38,10)` in raw, and control both.
7. No synthetic data is involved. The only authored objects are the three CSVs named above; none holds an
   amount.
