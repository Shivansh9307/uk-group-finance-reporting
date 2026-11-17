"""Checks of the plan load against the profiling outputs (`docs/profiling/data/plan_*.csv`).

The profiling code (`ukfr.profile.plans`) parsed the same workbooks with Python rules: the measure of an
Estimates sheet from its title, the best final plan per year, which PESA sections are department-group
tables and the 2023-24 consistency table. The load in `sql/` re-implements those rules in T-SQL, so each test
compares what the database holds with what the profiling wrote down. They read a database that `ukfr build`
has filled and run in both build scopes.
"""

from __future__ import annotations

import csv
from decimal import Decimal
from pathlib import Path

import pytest

DATA = Path(__file__).resolve().parents[2] / "docs" / "profiling" / "data"


def read(name: str) -> list[dict[str, str]]:
    with open(DATA / name, encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


@pytest.mark.db
def test_estimates_measure_comes_from_the_sheet_title(db):
    """Every sheet of every Estimates workbook gets the measure the profiling read from its title; the sheet
    called 'RDEL' in the 2022-23 Supplementary Estimate is the excluding-depreciation table."""
    expected = {(r["release"], r["sheet"]): r["measure"] for r in read("plan_estimates_inventory.csv")}
    got = {
        (r[0], r[1]): r[2]
        for r in db.query("SELECT DISTINCT edition, sheet, measure_from_title FROM stg.plan_estimates_line")
    }
    assert got == expected
    assert got[("2022-23-supps", "RDEL")] == "RDEL_EX_DEPN"
    assert got[("2022-23-mains", "RDEL ex")] == "RDEL_EX_DEPN"
    # the 2026-27 Main Estimate's only resource table is not titled 'excluding depreciation': measure stays RDEL
    # from the title, and the authored plan source moves it to the excluding-depreciation basis
    assert got[("2026-27-mains", "RDEL")] == "RDEL"
    final = {
        (r[0], r[1]): r[2]
        for r in db.query(
            "SELECT DISTINCT edition, sheet, measure FROM stg.plan_estimates_line WHERE edition = '2026-27-mains'"
        )
    }
    assert final[("2026-27-mains", "RDEL")] == "RDEL_EX_DEPN"


@pytest.mark.db
def test_the_final_plan_workbook_per_year_is_the_one_the_profiling_chose(db):
    expected = {
        (r["release"], r["sheet"])
        for r in read("plan_estimates_inventory.csv")
        if r["best_final_plan_for_year"] == "yes"
    }
    got = {
        (r[0], r[1])
        for r in db.query("SELECT DISTINCT edition, sheet FROM stg.plan_estimates_line WHERE is_final_plan = 1")
    }
    assert len(expected) == 14
    assert got == expected


MEASURES = {"RDEL", "RDEL_EX_DEPN", "CDEL", "TDEL", "RESOURCE_DEPT_AME", "CAPITAL_DEPT_AME", "ADMIN", "ADMIN_EX_DEPN"}


@pytest.mark.db
def test_pesa_department_group_sections_equal_the_profiling_inventory(db):
    """The T-SQL rules for 'which sections are department-group tables, and which measure' reproduce the
    profiling inventory for the nominal tables of the eight measures the plan uses."""
    expected = set()
    for r in read("plan_pesa_inventory.csv"):
        m = r["measure"]
        if r["grain"] == "department group" and m in MEASURES and "real terms" not in r["title"].lower():
            expected.add((r["release"], r["sheet"], r["section"], m))
    got = {
        (r[0], r[1], r[2], r[3])
        for r in db.query(
            "SELECT DISTINCT edition, sheet, section, measure_from_title "
            "FROM stg.plan_pesa_line WHERE row_kind = 'line'"
        )
    }
    # the ADMIN table of PESA 2026 is read as ADMIN from its title in both
    assert got == expected


def _sql_sums(db) -> dict[tuple[str, str, str], Decimal]:
    """(column label, group, measure) -> GBP thousands for the three sources the 2023-24 table compares."""
    out: dict[tuple[str, str, str], Decimal] = {}
    rows = db.query(
        """
        SELECT 'est' AS src, target_name, measure_from_title, SUM(amount_k)
        FROM stg.plan_estimates_line
        WHERE edition = '2023-24-supps' AND year_label = '2023-24' AND row_kind = 'line' AND line_role <> 'component'
          AND measure_from_title IN ('RDEL', 'RDEL_EX_DEPN', 'CDEL')
        GROUP BY target_name, measure_from_title
        UNION ALL
        SELECT 'pesa23', target_name, measure_from_title, SUM(amount_k)
        FROM stg.plan_pesa_line
        WHERE edition = '2023' AND year_label = '2023-24' AND status_label = 'plans'
          AND row_kind = 'line' AND line_role <> 'component'
          AND measure_from_title IN ('RDEL', 'RDEL_EX_DEPN', 'CDEL')
        GROUP BY target_name, measure_from_title
        UNION ALL
        SELECT 'pesa24', target_name, measure_from_title, SUM(amount_k)
        FROM stg.plan_pesa_line
        WHERE edition = '2024' AND year_label = '2023-24' AND status_label = 'outturn'
          AND row_kind = 'line' AND line_role <> 'component'
          AND measure_from_title IN ('RDEL', 'RDEL_EX_DEPN', 'CDEL')
        GROUP BY target_name, measure_from_title
        """
    )
    for src, name, measure, amount in rows:
        if amount is None:
            continue
        out[(src, name, measure)] = Decimal(amount)
    return out


@pytest.mark.db
def test_fy2023_24_consistency_figures_are_reproduced(db):
    """plan-sources.md section 13 (plan_consistency_2023_24.csv): the Estimates plan, the PESA 2023 plan and the
    PESA 2024 outturn for every Spending Review group and measure, to the pound thousand. The BUD outturn column
    needs the annual BUD, which another task loads, so it is not checked here."""
    columns = {
        "est": "Estimates 2023-24-supps gbp_thousand",
        "pesa23": "PESA 2023 (plans) gbp_thousand",
        "pesa24": "PESA 2024 (outturn) gbp_thousand",
    }
    non_department = {
        "[Reserves]": "Reserves",
        "[OBR allowance for shortfall]": "OBR allowance for shortfall",
        "[Adjustment for Budget Exchange]": "Budget Exchange adjustment",
        "[Single Intelligence Account]": "Single Intelligence Account",
    }
    sums = _sql_sums(db)
    groups = {
        r[0] for r in db.query("SELECT sr_group_name FROM dw.dim_sr_group WHERE member_type = 'spending_review_group'")
    }
    checked = 0
    totals = {k: Decimal(0) for k in ((s, m) for s in columns for m in ("RDEL", "RDEL_EX_DEPN", "CDEL"))}
    for row in read("plan_consistency_2023_24.csv"):
        name, measure = row["sr_group"], row["measure"]
        if name.startswith("TOTAL"):
            continue
        sql_name = non_department.get(name, name)
        if sql_name not in groups and name not in non_department:
            continue  # '[name]' lines the profiling left unmapped, several lines here (Levelling Up Fund)
        for key, col in columns.items():
            published = row[col]
            got = sums.get((key, sql_name, measure))
            if published == "":
                assert got is None, (name, measure, key, got)
            else:
                assert got == Decimal(published), (name, measure, key, got, published)
                checked += 1
        if sql_name in groups:
            for key in columns:
                totals[(key, measure)] += sums.get((key, sql_name, measure), Decimal(0))
    assert checked > 150
    for row in read("plan_consistency_2023_24.csv"):
        if row["sr_group"].startswith("TOTAL"):
            for key, col in columns.items():
                assert totals[(key, row["measure"])] == Decimal(row[col]), (row["measure"], key)


@pytest.mark.db
def test_no_pesa_or_estimates_name_is_mapped_to_a_group_that_does_not_exist(db):
    rows = db.query(
        """
        SELECT m.plan_name FROM stg.plan_name_map AS m
        LEFT JOIN dw.dim_sr_group AS g ON g.sr_group_name = m.target_name
        WHERE g.sr_group_key IS NULL
        """
    )
    assert rows == []
