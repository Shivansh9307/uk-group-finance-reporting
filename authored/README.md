# authored

Small tables I wrote by hand because no source publishes them: which key a code gets when its prefix
is not enough, what a department is called in a given period. They are not source data and never
enter a real total. Each file here is loaded by `ukfr build` into `authored.<file stem>`.

## Convention

- One CSV per table, UTF-8, LF line ends (`.gitattributes` pins `authored/*.csv`). The file name is
  the table name: lower case letters, digits and underscores.
- One row per fact. If a fact has two periods or two cases, it has two rows.
- Every row has an `evidence` column and a `note` column. `evidence` says where the fact comes from:
  the file, the profiling output or the release it was read in, with the numbers. `note` says why I
  decided what I did, in my own words, including what I am not sure of.
- Releases are written as the release label (`2023-06`). A blank `valid_from_release` means from the
  first release, a blank `valid_to_release` means open ended.
- I author every file here. The build never writes to them.

## How a file is loaded

`ukfr.stages.authored` (stage `authored`, scope `committed`, runs before the SQL) reads every
`authored/*.csv` with the standard `csv` module and creates `authored.<stem>` with a
`_load_order` column (1.. in file order) and one `nvarchar(max)` column per header name, in header
order. Every value is text exactly as written; an empty field is an empty string. The table carries
a description that says it is authored data. It is dropped and created again on every build, so it
always equals the file. A new file needs no Python: drop it in, and the next build loads it.

Typing, defaults and checks are T-SQL. A file is read by a `sql/stg/` file that converts it to a
typed table, stops the build on a label that does not exist, and has tests under `sql/tests/`. The
loader refuses a file with no header, a header that is not a plain identifier, a duplicate header
(ignoring case), the reserved name `_load_order`, or a row with the wrong number of fields.

## Register

| File | Table | Rows | What it holds | Read by |
|---|---|---|---|---|
| `department_name.csv` | `authored.department_name` | one per department number and naming period | the display name of each department number in each period, the labels the files use in that period, evidence | `stg.department_period`, `dw.dim_department` |
| `organisation_key_override.csv` | `authored.organisation_key_override` | one per code and period | the durable key a code gets where its three-letter prefix is not enough (prefix collisions, a prefix change, reused core department codes, a merger, a coding error) | `stg.organisation_key_override`, `dw.dim_organisation` |
| `account_flow.csv` | `authored.account_flow` | one per economic category code that the digit rule does not settle | whether the category is Expenditure, Income or Not applicable, with the profile figures and my reasoning | `stg.account_flow`, `dw.dim_account` |
| `current_structure_map.csv` | `authored.current_structure_map` | one per organisation and sub-segment, or per organisation | the department a line belongs to in the current structure where the rules cannot decide it: the review of the 15 BEIS sub-segments the November 2023 annual file disagreed on, three lines left in the DSIT group (marked estimated), and the departments that closed into another (DFID to FCDO, DIT to DBT) | `stg.current_structure_authored`, `dw.current_structure_line` |

All are labelled authored in the database (table description) and in the model that imports the
dimensions. None holds an amount.
