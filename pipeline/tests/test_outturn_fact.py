"""The profile control stage, and worked examples of the outturn revision-delta fact against the built database."""

from __future__ import annotations

import csv
from decimal import Decimal

import pytest

from ukfr.stages import all_stages, select_stages
from ukfr.stages.profile_controls import COLUMNS, PATH


def test_the_profile_stage_is_registered_with_committed_scope():
    by_name = {s.name: s for s in all_stages()}
    assert by_name["profile_controls"].scope == "committed"
    assert "profile_controls" in [s.name for s in select_stages("committed")]


def test_the_profile_file_has_the_columns_the_stage_expects(repo_root):
    with (repo_root / PATH).open(encoding="utf-8", newline="") as fh:
        assert next(csv.reader(fh)) == COLUMNS


# -- against the database -----------------------------------------------------------------------


@pytest.mark.db
def test_the_landed_profile_rows_equal_the_file(db, repo_root):
    with (repo_root / PATH).open(encoding="utf-8", newline="") as fh:
        rows = list(csv.DictReader(fh))
    landed = {r[0]: r for r in db.query("SELECT release, delta_rows_non_zero FROM raw.profile_inyear_delta_rowcount")}
    assert len(landed) == len(rows) == 31
    for r in rows:
        assert landed[r["release"]][1] == r["delta_rows_non_zero"]


@pytest.mark.db
def test_a_unit_error_line_is_added_then_reversed_and_both_rows_are_flagged(db):
    """NHP903 X903A002, April 2023: 4.1bn in September 2023, 4.1m in December 2023."""
    rows = db.query(
        """
        SELECT r.label, f.revision_no, f.amount_delta, f.dq_issue_id
        FROM dw.fact_outturn AS f
        JOIN dw.dim_release AS r ON r.release_key = f.release_key
        JOIN dw.dim_segment AS sg ON sg.segment_key = f.segment_key
        JOIN dw.dim_organisation AS o ON o.organisation_key = f.organisation_key
        WHERE o.organisation_code = 'NHP903' AND sg.sub_segment_code = 'X903A002' AND f.period_key = 202301
          AND f.account_key = (SELECT account_key FROM dw.dim_account WHERE economic_category_code = 'NA')
        ORDER BY f.release_key
        """
    )
    labels = [r[0] for r in rows]
    assert labels[:2] == ["2023-09", "2023-12"]
    first, second = rows[0], rows[1]
    assert (first[1], second[1]) == (0, 1)
    assert Decimal(first[2]) == Decimal("4100000000")
    assert Decimal(second[2]) == Decimal("4100000") - Decimal("4100000000")
    assert first[3] is not None and first[3] == second[3]
    assert sum(Decimal(r[2]) for r in rows[:2]) == Decimal("4100000")


@pytest.mark.db
def test_the_june_2019_period_zero_rows_are_in_the_fact_once_and_in_the_year_total(db):
    n, total = db.query(
        """
        SELECT COUNT(*), SUM(amount_delta) FROM dw.fact_outturn WHERE period_key = 201800
        """
    )[0]
    assert n == 71
    assert Decimal(total) == Decimal("269890")


@pytest.mark.db
def test_the_dimension_row_counts_the_documentation_states(db):
    counts = {
        name: db.scalar(f"SELECT COUNT(*) FROM dw.{name}")
        for name in (
            "dim_release",
            "dim_period",
            "dim_scenario",
            "dim_account",
            "dim_control_budget",
            "dim_segment",
            "dq_issue",
        )
    }
    assert counts["dim_release"] == 31
    assert counts["dim_period"] == 143
    assert counts["dim_scenario"] == 5
    assert counts["dim_control_budget"] == 6
    assert counts["dim_account"] == 1 + 127
    assert counts["dim_segment"] == 1 + 3765
