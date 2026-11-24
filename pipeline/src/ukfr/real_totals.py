"""The row counts and sums of the real facts, and the committed file that pins them.

`evidence/expected/real_fact_totals.csv` holds, per build scope and fact, the number of rows and the sum of
the amount column of each real fact table. `pipeline/tests/test_real_totals.py` fails when a build does not
match it, which is how a derived or authored object that leaks into a real total is caught. When a
legitimate change moves a real total, rerun the build for the scope and write the file in one place:

    uv run --project pipeline ukfr real-totals --write

The rows of the other scope are kept as they were.
"""

from __future__ import annotations

import csv
from decimal import Decimal
from pathlib import Path

from .db import Db

EXPECTED_CSV = Path("evidence") / "expected" / "real_fact_totals.csv"
HEADER = ["scope", "fact", "amount_column", "rows", "amount_sum"]

# (fact table, amount column, scopes in which the table exists). Real data only: no derived or authored table.
FACTS = [
    ("dw.fact_outturn", "amount_delta", ("committed", "full")),
    ("dw.fact_plan", "amount", ("committed", "full")),
    ("dw.fact_outturn_annual", "amount", ("full",)),
    ("dw.tac_fact", "value", ("full",)),
]


def build_scope(db: Db) -> str:
    return db.scalar(
        "SELECT CAST(value AS varchar(20)) FROM sys.extended_properties WHERE class = 0 AND name = N'ukfr_build_scope'"
    )


def measure(db: Db, scope: str) -> list[dict[str, str]]:
    """Rows and sum of every real fact that exists in `scope`, read from the database."""
    out = []
    for table, column, scopes in FACTS:
        if scope not in scopes:
            continue
        n, total = db.query(f"SELECT COUNT_BIG(*), SUM(CAST({column} AS decimal(38, 4))) FROM {table}")[0]
        out.append(
            {
                "scope": scope,
                "fact": table,
                "amount_column": column,
                "rows": str(n),
                "amount_sum": format(Decimal(total), "f"),
            }
        )
    return out


def read_expected(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def write_expected(path: Path, scope: str, measured: list[dict[str, str]]) -> None:
    """Replace the rows of `scope` and keep the rest, sorted by fact then scope."""
    kept = [r for r in (read_expected(path) if path.exists() else []) if r["scope"] != scope]
    rows = sorted(kept + measured, key=lambda r: (r["fact"], r["scope"]))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=HEADER, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
