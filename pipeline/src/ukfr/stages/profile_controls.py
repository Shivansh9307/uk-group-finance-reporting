"""Load stage for the profiled delta row counts: `docs/profiling/data/inyear_delta_rowcount.csv`.

The profile (`ukfr profile inyear`) counted, for every release, how many delta rows a revision-delta fact
would need. It worked on source codes and exact amounts, with code that shares nothing with the
warehouse SQL, so it is an independent control for `dw.fact_outturn`. This stage lands the file as it
is, untyped, in `raw.profile_inyear_delta_rowcount`; the comparison is T-SQL (`audit.delta_rowcount`).
"""

from __future__ import annotations

import csv

from . import Stage, StageContext

PATH = "docs/profiling/data/inyear_delta_rowcount.csv"
TABLE = "raw.profile_inyear_delta_rowcount"
COLUMNS = [
    "financial_year",
    "release",
    "release_no_in_year",
    "stacked_keys",
    "first_appearances",
    "changed",
    "vanished",
    "delta_rows_all",
    "delta_rows_non_zero",
]


def run(ctx: StageContext) -> dict[str, int]:
    path = ctx.repo_root / PATH
    with path.open(encoding="utf-8-sig", newline="") as fh:
        reader = csv.reader(fh)
        header = next(reader)
        if header != COLUMNS:
            raise ValueError(f"{PATH}: unexpected header {header}")
        rows = [r for r in reader if r]
    ctx.db.execute(f"DELETE FROM {TABLE};")
    ctx.db.insert_many(TABLE, COLUMNS, rows)
    ctx.log(f"  profile delta row counts: {len(rows)} rows")
    return {"profile_inyear_delta_rowcount": len(rows)}


STAGE = Stage(
    name="profile_controls",
    scope="committed",
    run=run,
    description="Land the profiled in-year delta row counts, the independent control for the outturn fact.",
)
