"""The current-structure map: the review of the BEIS lines the November 2023 annual file disagreed on, and the
split of the 204 BEIS sub-segments of June 2023 by rule.

The review set is derived here from the profile's cross-check file, so the test fails if a disagreement has no
authored row. The split is read from the database that `ukfr build` has filled.
"""

from __future__ import annotations

import csv

import pytest

DSIT = "SCIENCE"


def cross_check_rows(repo_root):
    path = repo_root / "docs" / "profiling" / "data" / "bud_beis_subsegment_crosscheck.csv"
    with path.open(encoding="utf-8", newline="") as fh:
        return [r for r in csv.DictReader(fh) if r["bud_vintage"] == "2023-11"]


def disagreements(repo_root):
    """Sub-segments where the in-year successor and the November 2023 annual file differ.

    Eight the profile sends to DSIT whose 2022-23 amount nets to zero in the annual file, seven it sends to
    DESNZ or DBT that still hold a value in the DSIT group.
    """
    out = []
    for r in cross_check_rows(repo_root):
        succ, status = r["inyear_successor_departments"], r["bud_status"]
        if not succ or "/" in succ:
            continue
        in_dsit = DSIT in succ
        if status == "nets_to_zero" and in_dsit:
            out.append(r["sub_segment_code"])
        elif status == "one_group" and not in_dsit and DSIT in r["bud_department_group_names"]:
            out.append(r["sub_segment_code"])
    return sorted(out)


def authored_rows(repo_root):
    with (repo_root / "authored" / "current_structure_map.csv").open(encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def test_the_review_set_is_the_fifteen_of_the_profile(repo_root):
    codes = disagreements(repo_root)
    assert len(codes) == 15
    gross = sum(
        abs(int(r["inyear_amount_full_year"])) for r in cross_check_rows(repo_root) if r["sub_segment_code"] in codes
    )
    assert 1_100_000 < gross < 1_110_000  # 1.10bn gross in GBP thousands, as the profile says


def test_every_disagreement_has_an_authored_row_that_states_the_decision(repo_root):
    rows = authored_rows(repo_root)
    by_code = {r["sub_segment_code"]: r for r in rows if r["sub_segment_code"]}
    for code in disagreements(repo_root):
        row = by_code.get(code)
        assert row is not None, f"{code} has no row in authored/current_structure_map.csv"
        assert row["review_set"] == "beis_bud_2023_11", code
        assert row["decision"].startswith(("follow the restated annual file", "keep the in-year successor")), code
        assert row["evidence"].strip() and row["note"].strip(), code


@pytest.mark.db
def test_the_disagreements_are_decided_by_their_authored_rows_in_the_built_map(db, repo_root):
    codes = disagreements(repo_root)
    placeholders = ",".join("?" for _ in codes)
    rows = db.query(
        f"SELECT sub_segment_code, COUNT(*), SUM(CASE WHEN method = 'authored line' THEN 1 ELSE 0 END) "
        f"FROM dw.current_structure_line WHERE sub_segment_code IN ({placeholders}) AND durable_key <> 'BIS.DSIT' "
        f"AND authored_row IS NOT NULL GROUP BY sub_segment_code",
        tuple(codes),
    )
    assert {r[0] for r in rows} == set(codes)
    assert all(r[1] == r[2] for r in rows)


@pytest.mark.db
def test_the_204_beis_sub_segments_split_by_rule_as_documented(db):
    """The profile found 194 with one successor, 1 with two and 9 with none. By the rules in the map the split is
    the one below; the differences are listed in docs/data-dictionary/current-structure.md."""
    rows = db.query(
        """
        WITH beis AS (
            SELECT DISTINCT m.organisation_key, s.sub_segment_code
            FROM stg.inyear_snapshot AS s
            JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
            JOIN dw.dim_department AS d ON d.department_key = m.department_key
            WHERE s.release = '2023-06' AND d.department_number = '084'
        )
        SELECT COALESCE(l.rule_method, l.method), COUNT(*)
        FROM beis AS b
        JOIN dw.current_structure_line AS l
          ON l.organisation_key = b.organisation_key AND l.sub_segment_code = b.sub_segment_code
        GROUP BY COALESCE(l.rule_method, l.method)
        """
    )
    assert dict(rows) == {
        "sub-segment code": 36,
        "sub-segment name": 79,
        "organisation current department": 81,
        "unallocated former department": 8,
    }


@pytest.mark.db
def test_a_line_of_an_organisation_with_a_home_never_follows_the_code_of_another_department(db):
    """The code rule is only for an organisation whose department closed. The audit table lists the lines it would
    have moved; none of them may carry the code method."""
    assert (
        db.scalar(
            "SELECT COUNT(*) FROM audit.current_structure_code_rule_rejected AS r "
            "JOIN dw.current_structure_line AS l "
            "ON l.organisation_key = r.organisation_key AND l.sub_segment_code = r.sub_segment_code "
            "WHERE l.method <> 'organisation current department'"
        )
        == 0
    )
    assert db.scalar("SELECT COUNT(*) FROM audit.current_structure_code_rule_rejected") > 0


@pytest.mark.db
def test_is_current_and_is_live_differ_only_for_the_three_departments_the_partial_september_release_omits(db):
    """`dim_department.is_current` is false for the National Audit Office, the Crown Estate Office and the Judicial
    Pensions Scheme (they report in June 2026 and not in the partial September 2026 release); `is_live` is true."""
    rows = db.query(
        "SELECT d.department_number, d.is_current, c.is_live FROM dw.dim_department AS d "
        "JOIN dw.current_structure_department AS c ON c.department_key = d.department_key "
        "WHERE d.is_current <> c.is_live ORDER BY d.department_number"
    )
    assert [(r[0], bool(r[1]), bool(r[2])) for r in rows] == [
        ("014", False, True),
        ("050", False, True),
        ("908", False, True),
    ]
