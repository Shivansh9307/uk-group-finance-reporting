# Departmental workforce files: what is there

Departments publish monthly workforce management information (headcount, full-time equivalent and paybill for each
organisation they are responsible for) on gov.uk, one collection per department, under the Cabinet Office transparency
requirement. This page records what the files really hold, which departments and months I found, and what is missing,
before anything was built on them. What the build does with them is in
[../data-dictionary/workforce.md](../data-dictionary/workforce.md).

Every claim is labelled **tested** (the command, and where the result is) or **designed** (not run).

Commands, run on 2026-11-24 on the development machine:

```
uv run --project pipeline ukfr fetch --source workforce_mi        # 1,453 files downloaded, 0 errors, 2,895 requests
uv run --project pipeline ukfr build --scope full --recreate      # reads them (stage `workforce`, 60 s of the 18 minute build)
```

## What I checked against the brief

| Statement | Result |
|---|---|
| The files carry no organisation codes, only names | **tested.** Every file has `Organisation name`, `Organisation type` and `Main, parent or sponsoring department` and nothing else that identifies a body (reader: `pipeline/src/ukfr/readers/workforce.py`). The names alternate between spellings, so the build maps them with an authored list |
| Four formats, two templates | **tested**, with a correction: csv (1,281 files read), xlsx (111) and ods (41) are in the months I use; no xls file is (the DHSC xls files are all before April 2018, so the xls path of the reader was run once by hand on one of them and is not covered by a committed test). The older and the newer Cabinet Office template are both there, and the newer one changed its non-payroll columns twice. A third variant is a file whose header rows were cut out by the publisher (BEIS, September 2018 to May 2021) |
| Paybill is not split by grade | **tested.** Paybill is split by pay element (salary, allowances, non-consolidated performance payments, overtime, employer pension, employer national insurance), never by grade, so a grade-mix effect cannot be computed. Headcount and full-time equivalent are split by six grade groups |
| Enough departments publish | **tested.** 20 series from 23 gov.uk collections (a department that changed its name has a collection for each name) have files in the months I use; 19 of them reach the fact (HM Land Registry is counted from the BEIS series). The model has 56 current department rows, of which 19 publish here (34%): DWP, DHSC, DfE, MOD, HMRC, DfT, Defra, FCDO and the other big employers except the Home Office and the Ministry of Justice, which are not in the source. The ones with no collection are listed below |

## Which departments publish

A series is the run of collections of one department under its successive names (MHCLG, then DLUHC, then MHCLG; FCO, then
FCDO). Months are those from April 2018, the first month inside the OSCAR releases. "Missing" is the calendar months
between the first and last month for which I have no readable file.

| Series | First month | Last month | Months read | Missing | Files | Not read | Formats | Header layouts |
|---|---|---|---|---|---|---|---|---|
| BEIS (to August 2023) | 2018-04 | 2023-08 | 60 | 5 | 66 | 6 | csv | no group row, single row |
| CMA | 2020-12 | 2026-09 | 66 | 4 | 68 | 2 | csv | single row |
| DBT | 2023-07 | 2026-10 | 40 | 0 | 40 | 0 | csv | single row |
| DCMS | 2025-01 | 2026-09 | 21 | 0 | 21 | 0 | csv, xlsx | single row |
| Defra | 2018-05 | 2026-09 | 72 | 29 | 142 | 0 | csv, xlsx | multi-row, single row |
| DESNZ | 2023-09 | 2026-10 | 38 | 0 | 38 | 0 | csv | single row |
| DfE | 2018-04 | 2026-10 | 103 | 0 | 103 | 0 | csv | multi-row, single row |
| DfT | 2018-04 | 2026-10 | 102 | 1 | 103 | 1 | csv | multi-row, single row |
| DHSC | 2018-04 | 2026-09 | 102 | 0 | 109 | 0 | csv, ods, xlsx | multi-row, single row |
| DSIT | 2023-09 | 2026-09 | 37 | 0 | 37 | 0 | csv | single row |
| DWP | 2018-04 | 2026-08 | 100 | 1 | 101 | 1 | csv, ods | multi-row, single row |
| FCDO (and FCO before it) | 2018-04 | 2026-09 | 92 | 10 | 92 | 0 | csv | single row |
| FSA | 2021-06 | 2026-10 | 65 | 0 | 65 | 0 | csv, xlsx | single row |
| HM Land Registry (own collection) | 2018-04 | 2019-11 | 15 | 5 | 15 | 0 | csv | multi-row |
| HMRC | 2018-04 | 2026-10 | 103 | 0 | 103 | 0 | csv | multi-row, single row |
| HM Treasury | 2021-04 | 2026-10 | 24 | 43 | 24 | 0 | xlsx | multi-row, single row |
| MHCLG (and DLUHC) | 2018-04 | 2026-09 | 99 | 3 | 102 | 3 | csv | multi-row, single row |
| MOD | 2018-04 | 2026-09 | 102 | 0 | 105 | 0 | csv, ods, xlsx | multi-row, single row |
| NCA | 2025-04 | 2026-10 | 19 | 0 | 19 | 0 | ods | single row |
| UK Export Finance | 2018-04 | 2026-08 | 93 | 8 | 100 | 7 | csv | multi-row, single row |

**Tested**: `audit.workforce_department_summary` (committed copy `evidence/full/workforce_department_summary.csv`), from
`ukfr build --scope full --recreate`. "Months read" counts the months with a primary file that the reader could read.
Where one month is published in several formats every copy is read and one is primary (80 months have a second copy:
70 Defra, 7 DHSC, 3 MOD).

### Gaps, and why

| Gap | What I found |
|---|---|
| Defra, 2018-07 to 2020-11 | The collection has files for May and June 2018 and then none until December 2020 (**tested**: the collection listing, `data/manifest/files.csv`) |
| HM Treasury, 2021-07 to 2025-01 | The collection lists April to June 2021 and then February 2025 onwards. Nothing in between (**tested**, same way) |
| FCDO, April to December 2022 and May 2026 | No file in the collection for those months |
| UKEF, June to December 2020 | The files are in a layout with the organisation name in the second column and no type column; I do not read it (listed in `data/manifest/workforce_skipped_files.csv`). December 2024 has no file |
| BEIS, five months | One file has a malformed header, two have a header cell that says only "Headcount", one has a column headed "4", and October 2021 has two data sheets (listed with reasons in the skip list) |
| CMA, December 2020 to March 2021 | A file with one row per month and no organisation name; I do not read it |
| MHCLG, June 2019 and April and May 2023 | A header cell holds spreadsheet formula text in one; a non-payroll total is headed in a different wording in the other two |
| DfT, December 2020; DWP, April 2025 | One header problem each (a repeated "Total", a column headed "total bill") |
| HM Land Registry, 2018-11 to 2019-03 | Its own collection has the file for fifteen months only. The same body is in the BEIS series for every month, which is the copy I count |

Twenty files in all are not read, each with its reason in `data/manifest/workforce_skipped_files.csv`. The stage fails if
a file it cannot read is not on that list, and if a file on the list can be read (**tested**:
`pipeline/tests/test_workforce.py`, `pipeline/tests/test_workforce_load.py`).

### Not published, or not usable

| Body | Finding |
|---|---|
| Home Office, Ministry of Justice, Cabinet Office, ONS | I found no workforce management information collection for them (**tested**: searches of the gov.uk search API for each name returned no collection) |
| Office of Rail and Road | The collection has 70 documents, all HTML tables with no file, so there is nothing to fetch |
| Attorney General's Office, GLD, HMCPSI, CPS | One file a year; the one I opened (2025-26, ods) has a sheet per month. I did not build for a file that holds twelve months |
| DfID, DIT | DFID's collection ends in 2014; I found no DIT collection |

## How the files are laid out

Columns, in the order the template has them (**tested** by the reader on every file):

1. Year, Month, Organisation name, Organisation type, Main parent or sponsoring department. Files before about 2020 have
   no Year and Month: the month comes from the page.
2. Payroll staff: headcount and full-time equivalent for AO/AA, EO, SEO/HEO, Grade 6/7, SCS, Other and Total.
3. Non-payroll staff. Older template: Agency, Interim, Specialist contractors, Consultants, Total (headcount and
   full-time equivalent). Newer template: Admin and clerical, Interim and specialist and medical, Other contingent, Total
   contingent (headcount and full-time equivalent) and the number of consultancy contracts.
4. Grand total headcount and full-time equivalent.
5. Payroll staff costs: salary, allowances, non-consolidated performance payments, overtime, employer pension, employer
   national insurance, total paybill.
6. Non-payroll costs: contingent labour, consultancy, total; then the grand total.
7. A comments column in some files.

| Fact | Result |
|---|---|
| Unit of paybill | Pounds for the month (**tested**: for example HM Treasury's June 2021 payroll paybill is £12,466,790 for 2,022 full-time equivalent, about £6,165 a month each). Headcount and full-time equivalent are people |
| Files and layouts read | 1,433 of 1,453 files: 971 single-row headers, 273 multi-row headers (three header rows with merged group cells), 37 with the group row removed (BEIS) |
| Rows | 17,798 non-blank rows in all the copies read. In the primary copies there are 15,941: 5,997 are spare template rows (no organisation name, every value zero or blank) that some departments leave in, 6 have values and no name, and 9,938 have a name |
| Values | 435,354 numeric cells loaded. 3,554 cells that are not numbers are quarantined: `.` (1,574), `£0.00` with a damaged pound sign (713), `No data` (373), `(.)` (148), `£-` (94), `-` (92) and a few others |
| Comment columns | 520 comment or note columns are not read; `raw.workforce_ignored_column` lists them. The 3,554 non-numeric cells above are in 115 files |
| Organisation names | 228 distinct published names across the series. Spellings change inside a series (`Advisory Conciliation & Arbitration Service (ACAS)` and `Advisory Conciliation and Arbitration Service`), bodies are renamed (Monitor, NHS Digital, Mining Remediation Authority), and some names are misspelt (`MHS Business Servises Authority`, `Transport Focus NOT Passenger Focus`) |
| Row arithmetic | In the files read, 18 rows have a payroll full-time equivalent total that is not the sum of its grade columns (more than 1 person out), 21 for headcount and 26 for paybill (more than £1,000). They are listed in `audit.workforce_row_arithmetic`; I do not correct them |
| Template rows that are not organisations | A `Total` row in six Defra months, a `HM Revenue and Customs combined total` row in two HMRC months, and footnote lines in DHSC files. They are excluded in the authored map, each with its reason |
| Mislabelled months | 38 rows say a month that is not the month of their file (a carry-over or a typo): MOD's September 2022 file says November, its August and December 2022 files say July and November; one CMA file holds eight earlier months. They are quarantined and the month they name has its own file |

### Limitations I state rather than hide

- **No grade-mix effect.** Paybill is not split by grade. A bridge can split a change into volume (full-time equivalent),
  rate (paybill per full-time equivalent) and organisation mix, and no further.
- **Non-payroll full-time equivalent changed definition.** The older template's "total non-payroll" included consultants;
  the newer one counts consultancy as a number of contracts. The fact uses contingent labour (agency, interim, specialist,
  other contingent), which is one definition through the period, and never the old total.
- **Rounded csv copies.** Where a month is published as csv and as a spreadsheet, Defra's csv has full-time equivalent
  rounded to whole people; the spreadsheet is to two or four decimal places. The build prefers the copy with the most rows
  that have a name and a value, then the spreadsheet.
- **Departments are not the whole of central government.** The Home Office, the Ministry of Justice, the Cabinet Office and
  ONS are not in this source.
- **Which months have what.** See the table in the data dictionary; the first month with any file for a department is
  not always April 2018.
