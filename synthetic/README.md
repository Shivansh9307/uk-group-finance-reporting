# synthetic

Invented data. Nothing here is a published figure, and nothing here holds an amount (the what-if settings hold percentages). Each file is loaded by `ukfr build`
into `synthetic.<file stem>`, a table that its own file in `sql/synthetic/` creates with typed columns and a check that
every row says `synthetic`.

## Convention

- One CSV per table, UTF-8, LF line ends (`.gitattributes` pins `synthetic/*.csv`). The file name is the table name.
- Every row has a `data_class` column that says `synthetic`; the table refuses any other value.
- Names are invented and use the reserved domain `example.org`, so no row can be a real person; a check refuses any other domain (the what-if file has no names).
- A synthetic table may filter or label real data. It never holds an amount and no real total reads it.
  The register in the repository [README](../README.md#register-of-real-authored-derived-and-synthetic-data) lists every file,
  and `pipeline/tests/test_register.py` fails if a file or table is missing from it or a real fact reads one.

## Files

| File | Table | What it holds |
|---|---|---|
| `user_department.csv` | `synthetic.user_department` | which departments of the current structure each invented user may see, for the row-level security roles of the model; see [docs/security.md](../docs/security.md) |
| `whatif_parameter.csv` | `synthetic.whatif_parameter` | five invented what-if settings (a pay award and a headcount change in per cent) for the allocation page; the base pay award is the ONS CPI annual rate for 2025, every other value is invented; see [docs/data-dictionary/allocation.md](../docs/data-dictionary/allocation.md) |

A user that is in no row (for example `nobody@example.org`, used by the tests) sees nothing: the unmapped case is the absence of a row.
