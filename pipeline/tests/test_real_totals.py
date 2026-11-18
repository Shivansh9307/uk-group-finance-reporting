"""Nothing derived, authored or synthetic reaches a real total.

The real facts are pinned by row count and sum in `evidence/expected/real_fact_totals.csv`, one set of
rows per build scope. A derived table (the phasing profile, the phased plan), an authored mapping or a
change to a bridge that added to or took from a real fact would move one of these numbers and fail here.
A legitimate change to a real total is made in one place: rebuild, run `ukfr real-totals --write`, review the
diff of the CSV and commit it with the change that explains it.
"""

from __future__ import annotations

import pytest

from ukfr import real_totals

pytestmark = pytest.mark.db


def test_the_real_facts_have_the_row_counts_and_sums_pinned_in_the_expectation_file(db, repo_root):
    scope = real_totals.build_scope(db)
    expected = {
        r["fact"]: r for r in real_totals.read_expected(repo_root / real_totals.EXPECTED_CSV) if r["scope"] == scope
    }
    measured = {r["fact"]: r for r in real_totals.measure(db, scope)}
    assert set(measured) == set(expected), (scope, sorted(set(measured) ^ set(expected)))
    for fact, got in measured.items():
        want = expected[fact]
        assert (got["rows"], got["amount_sum"]) == (want["rows"], want["amount_sum"]), (
            f"{fact} in scope {scope}: got {got['rows']} rows, sum {got['amount_sum']}; pinned "
            f"{want['rows']} rows, sum {want['amount_sum']}. If this is a legitimate change, run "
            "`ukfr real-totals --write` and commit the file."
        )


def test_only_the_two_phasing_tables_carry_a_derived_flag_and_no_real_fact_does(db):
    """The derived tables are exactly the phasing profile and the phased plan, all rows flagged, and the real
    facts have no `is_derived` column that could hide a derived row among real ones."""
    rows = db.query(
        "SELECT s.name + '.' + t.name FROM sys.tables AS t JOIN sys.schemas AS s ON s.schema_id = t.schema_id "
        "JOIN sys.columns AS c ON c.object_id = t.object_id AND c.name = 'is_derived' "
        "WHERE s.name = 'dw' AND (t.name LIKE 'fact[_]%' OR t.name LIKE 'plan[_]%') ORDER BY 1"
    )
    flagged = {r[0] for r in rows}
    assert flagged == {"dw.fact_plan_phased", "dw.plan_phasing_profile"}, flagged
    for table in flagged:
        assert db.scalar(f"SELECT COUNT_BIG(*) FROM {table} WHERE is_derived <> 1") == 0
