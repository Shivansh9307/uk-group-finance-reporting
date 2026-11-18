"""Checks of the plan phasing objects that need a file outside the database or the Python standard library.

The pure-SQL invariants are in `sql/tests/55x`. The two checks here compare the build with the profiling output
(`docs/profiling/data/plan_consistency_2023_24.csv`) and with the SQL files themselves.
"""

from __future__ import annotations

import csv
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

import pytest

BUD_COLUMN = "BUD BUD_23-24.xlsx (outturn) gbp_thousand"
BUD_VINTAGE = "2025-11"  # the annual release the profiling read as BUD_23-24.xlsx


@pytest.fixture(scope="module")
def annual(db):
    if db.scalar("SELECT OBJECT_ID(N'dw.outturn_plan_basis_annual')") is None:
        pytest.skip("this database was built without --scope full")
    return db


@pytest.mark.db
@pytest.mark.localdata
def test_annual_plan_basis_reproduces_the_fy2023_24_bud_column(annual, repo_root):
    """Every group and measure of the profiling's consistency table that has a BUD figure comes out of
    dw.outturn_plan_basis_annual to the thousand pound; the TOTAL row is the sum of the mapped groups."""
    with open(
        repo_root / "docs" / "profiling" / "data" / "plan_consistency_2023_24.csv", encoding="utf-8", newline=""
    ) as fh:
        rows = list(csv.DictReader(fh))
    got = {
        (name, measure): amount
        for name, measure, amount in annual.query(
            "SELECT g.sr_group_name, a.measure, a.amount FROM dw.outturn_plan_basis_annual AS a "
            "JOIN dw.dim_sr_group AS g ON g.sr_group_key = a.sr_group_key "
            "WHERE a.financial_year = '2023-24' AND a.vintage = ?",
            (BUD_VINTAGE,),
        )
    }
    compared = 0
    total_expected: dict[str, Decimal] = {}
    for r in rows:
        text = r[BUD_COLUMN].strip()
        if not text:
            continue
        want = Decimal(text)
        if r["sr_group"].startswith("TOTAL"):
            total_expected[r["measure"]] = want
            continue
        have = got.get((r["sr_group"], r["measure"]))
        assert have is not None, f"no annual row for {r['sr_group']} {r['measure']}"
        assert have.quantize(Decimal(1), rounding=ROUND_HALF_UP) == want.quantize(Decimal(1)), (
            r["sr_group"],
            r["measure"],
            have,
            want,
        )
        compared += 1
    assert compared >= 3 * 20, compared
    assert set(total_expected) == {"RDEL", "RDEL_EX_DEPN", "CDEL"}
    for measure, want in total_expected.items():
        # the TOTAL row is the sum of the groups the profiling mapped; groups outside that list have no BUD figure
        have = sum(v for (name, m), v in got.items() if m == measure)
        assert have.quantize(Decimal(1), rounding=ROUND_HALF_UP) == want.quantize(Decimal(1)), (measure, have, want)


def test_only_the_phasing_files_read_the_phased_plan():
    """Nothing but dw/560 (which builds it) and the audit summary may use dw.fact_plan_phased, apart from the DROP that
    keeps the build re-runnable."""
    sql = Path(__file__).resolve().parents[2] / "sql"
    allowed = {"dw/560_fact_plan_phased.sql", "audit/555_plan_phasing_summary.sql"}
    readers = sorted(
        p.relative_to(sql).as_posix()
        for p in sql.rglob("*.sql")
        if p.parent.name != "tests"
        and any(
            "fact_plan_phased" in line and not line.lstrip().upper().startswith(("DROP", "--"))
            for line in p.read_text(encoding="utf-8").splitlines()
        )
    )
    assert set(readers) == allowed, readers
