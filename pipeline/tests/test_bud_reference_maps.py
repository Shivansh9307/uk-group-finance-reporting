"""The reference maps and the controls built from the BUD and PSS loads reproduce the profiling outputs.

The profiling CSVs under `docs/profiling/data/` were written by `ukfr profile bud` and `ukfr profile plans`,
which read the workbooks with their own code and aggregate them in Python. The build reads the same
workbooks into `raw.oscar_bud` and builds the maps in T-SQL. Agreement is therefore two routes to the same
numbers. These tests need a database built with `--scope full`; against a committed-scope database they
skip.
"""

from __future__ import annotations

import csv
from collections import defaultdict
from decimal import Decimal

import pytest

pytestmark = [pytest.mark.db, pytest.mark.localdata]

PROFILE = "docs/profiling/data"


@pytest.fixture(scope="module")
def full(db):
    if db.scalar("SELECT OBJECT_ID(N'stg.bud_sr_group_by_organisation')") is None:
        pytest.skip("this database was built without --scope full")
    return db


def profile_rows(repo_root, name):
    with open(repo_root / PROFILE / name, encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def years_union(texts) -> str:
    return " ".join(sorted({y for t in texts for y in t.split()}))


def vintages_union(texts) -> str:
    return " ".join(sorted({v for t in texts for v in t.split()}))


def test_department_group_map_reproduces_the_profile(full, repo_root):
    expected = {}
    for r in profile_rows(repo_root, "bud_department_group_map.csv"):
        key = tuple(r[c] for c in ("department_group_code", "department_group_name", "sr_group_code", "sr_group_name",
                                   "pesa_group_code", "pesa_group_name"))  # fmt: skip
        expected[key] = (r["vintages"], r["financial_years"], int(r["rows"]), r["in_latest_vintage"] == "Y")
    got: dict[tuple, list] = defaultdict(lambda: [[], [], 0, False])
    for v, *key, years, n, latest in full.query(
        "SELECT vintage, department_group_code, department_group_name, sr_group_code, sr_group_name, pesa_group_code, "
        "pesa_group_name, financial_years, source_rows, is_latest_vintage FROM stg.bud_department_group_map"
    ):
        g = got[tuple(key)]
        g[0].append(v)
        g[1].append(years)
        g[2] += n
        g[3] = g[3] or bool(latest)
    assert {k: (vintages_union(v[0]), years_union(v[1]), v[2], v[3]) for k, v in got.items()} == expected
    assert len(expected) == 73


def test_organisation_type_map_reproduces_the_profile(full, repo_root):
    cols = ("organisation_code", "organisation_name", "organisation_type_code", "organisation_type_l1_code",
            "organisation_type_l1_name", "department_group_code")  # fmt: skip
    expected = {}
    for r in profile_rows(repo_root, "bud_organisation_type.csv"):
        expected[tuple(r[c] for c in cols)] = (r["vintages"], r["financial_years"], int(r["rows"]),
                                               r["in_latest_vintage"] == "Y")  # fmt: skip
    got: dict[tuple, list] = defaultdict(lambda: [[], [], 0, False])
    for v, *key, years, n, latest in full.query(
        "SELECT vintage, organisation_code, organisation_name, organisation_type_code, organisation_type_l1_code, "
        "organisation_type_l1_name, department_group_code, financial_years, source_rows, is_latest_vintage "
        "FROM stg.bud_organisation_type"
    ):
        g = got[tuple(key)]
        g[0].append(v)
        g[1].append(years)
        g[2] += n
        g[3] = g[3] or bool(latest)
    assert {k: (vintages_union(v[0]), years_union(v[1]), v[2], v[3]) for k, v in got.items()} == expected
    assert len({k[0] for k in expected}) == 321


def test_account_hierarchy_reproduces_the_profile(full, repo_root):
    cols = ("economic_category_code", "economic_category_name", "economic_group_code", "economic_group_name",
            "economic_budget_code")  # fmt: skip
    expected = {
        tuple(r[c] for c in cols): (int(r["n_chart_of_accounts_l5_codes"]), r["vintages"], r["financial_years"],
                                    int(r["rows"]), r["in_latest_vintage"] == "Y")
        for r in profile_rows(repo_root, "bud_account_hierarchy.csv")
    }  # fmt: skip
    got = {
        tuple(row[:5]): (row[5], row[6], row[7], row[8], bool(row[9]))
        for row in full.query(
            "SELECT economic_category_code, economic_category_name, economic_group_code, economic_group_name, "
            "economic_budget_code, n_chart_of_accounts_l5_codes, vintages, financial_years, source_rows, "
            "is_latest_vintage FROM stg.bud_account_hierarchy"
        )
    }
    assert got == expected
    assert len({k[0] for k in expected}) == 128


def test_sr_group_by_organisation_agrees_with_the_department_group_map(full):
    """Every (department group, SR group) pair of an organisation row is a pair of the department group map."""
    bad = full.query(
        "SELECT o.vintage, o.financial_year, o.organisation_code, o.department_group_code, o.sr_group_code "
        "FROM stg.bud_sr_group_by_organisation AS o "
        "WHERE NOT EXISTS (SELECT 1 FROM stg.bud_department_group_map AS m WHERE m.vintage = o.vintage "
        "AND m.department_group_code = o.department_group_code AND m.sr_group_code = o.sr_group_code)"
    )
    assert not bad, bad[:5]


def test_pss_against_bud_by_group_reproduces_the_profile(full, repo_root):
    """The profile compared PSS with the November 2025 BUD by SR group, summing every row of the workbook.
    The build leaves out the rows with STATUS_CODE 'Closed' (duplicates of other rows). So every line of the
    profile file that has both sides must equal the audit table's SR GROUP row exactly, apart from the Closed
    rows of that group, year and measure, which must account for the whole difference."""
    audit = {
        (r[0], r[1], r[2]): (r[3], r[4])
        for r in full.query(
            "SELECT financial_year, sr_group_name, measure, pss_amount, oscar_amount FROM audit.pss_vs_outturn "
            "WHERE comparison = 'BUD' AND level = 'SR GROUP'"
        )
    }
    closed = {
        (r[0], r[1], r[2]): r[3]
        for r in full.query(
            "SELECT LEFT(year_no, 4) + '-' + RIGHT(year_no, 2), sr_group_long_name, "
            "CASE WHEN economic_budget_code = 'CAPITAL' THEN 'CDEL' "
            "WHEN economic_ringfence_code <> 'RINGFENCED' THEN 'RDEL_EX_DEPN' ELSE 'RDEL_DEPN' END, SUM(amount) "
            "FROM raw.oscar_bud WHERE vintage = '2025-11' AND status_code = 'Closed' "
            "AND control_budget_l1_long_name = 'DEL' AND economic_budget_code IN ('RESOURCE', 'CAPITAL') "
            "GROUP BY LEFT(year_no, 4) + '-' + RIGHT(year_no, 2), sr_group_long_name, "
            "CASE WHEN economic_budget_code = 'CAPITAL' THEN 'CDEL' "
            "WHEN economic_ringfence_code <> 'RINGFENCED' THEN 'RDEL_EX_DEPN' ELSE 'RDEL_DEPN' END"
        )
    }
    checked = with_closed = 0
    for r in profile_rows(repo_root, "pss_vs_bud_by_group.csv"):
        if r["measure"] == "RDEL" or not r["pss_gbp_thousand"] or not r["bud_gbp_thousand"]:
            continue
        key = (r["fiscal_year"], r["sr_group"], r["measure"])
        pss, bud = audit[key]
        assert pss == Decimal(r["pss_gbp_thousand"]), r
        c = closed.get(key, Decimal(0))
        assert bud + c == Decimal(r["bud_gbp_thousand"]), (r, c)
        checked += 1
        with_closed += 1 if c else 0
    assert checked > 100 and 0 < with_closed < 20


def test_bud_totals_reproduce_the_profile_reconciliation(full, repo_root):
    """`bud_inyear_reconciliation_total.csv`: BUD amounts equal exactly, in-year amounts to the staging
    rounding (four decimals, zero rows dropped), for every year and vintage."""
    got = {
        (r[0], r[1], r[2]): (r[3], r[4])
        for r in full.query(
            "SELECT financial_year, vintage, level, inyear_amount, bud_amount FROM audit.bud_vs_inyear_del"
        )
    }
    rows = profile_rows(repo_root, "bud_inyear_reconciliation_total.csv")
    assert len(rows) == len(got) == 60
    for r in rows:
        iy, bud = got[(r["financial_year"], r["bud_vintage"], r["level"])]
        assert bud == Decimal(r["bud_amount"]), r
        assert abs(iy - Decimal(r["inyear_amount"])) < Decimal("0.01"), r


def test_bud_totals_reproduce_the_published_comparison_lines(full, repo_root):
    """`bud_pesa_check.csv` holds the November 2025 BUD sums that the profile compared with PESA."""
    sums = {
        (fy, m): total
        for fy, m, total in full.query(
            "SELECT financial_year, "
            "CASE WHEN control_budget_code = 'DEL' AND economic_budget_code = 'RESOURCE' THEN 'Total resource DEL' "
            "WHEN control_budget_code = 'DEL' AND economic_budget_code = 'CAPITAL' THEN 'Total capital DEL' "
            "WHEN control_budget_detail_code = 'DEPT AME' AND economic_budget_code = 'RESOURCE' "
            "THEN 'Total resource departmental AME' "
            "WHEN control_budget_detail_code = 'DEPT AME' AND economic_budget_code = 'CAPITAL' "
            "THEN 'Total capital departmental AME' END AS m, SUM(amount) "
            "FROM dw.fact_outturn_annual WHERE vintage = '2025-11' GROUP BY financial_year, "
            "CASE WHEN control_budget_code = 'DEL' AND economic_budget_code = 'RESOURCE' THEN 'Total resource DEL' "
            "WHEN control_budget_code = 'DEL' AND economic_budget_code = 'CAPITAL' THEN 'Total capital DEL' "
            "WHEN control_budget_detail_code = 'DEPT AME' AND economic_budget_code = 'RESOURCE' "
            "THEN 'Total resource departmental AME' "
            "WHEN control_budget_detail_code = 'DEPT AME' AND economic_budget_code = 'CAPITAL' "
            "THEN 'Total capital departmental AME' END"
        )
    }
    rows = profile_rows(repo_root, "bud_pesa_check.csv")
    assert rows
    for r in rows:
        assert sums[(r["financial_year"], r["pesa_line"])] == Decimal(r["bud_2025_11_gbp_000"]), r


def test_the_organisation_match_reproduces_the_profile(full, repo_root):
    expected = {
        r["organisation_code"]: (r["in_inyear_2026-09"] == "Y", r["in_bud_2025-11"] == "Y", r["same_prefix_in_bud"])
        for r in profile_rows(repo_root, "bud_inyear_org_match.csv")
    }
    got = {
        r[0]: (bool(r[1]), bool(r[2]), r[3])
        for r in full.query(
            "SELECT organisation_code, in_inyear, in_bud, same_prefix_in_bud FROM audit.bud_inyear_org_match"
        )
    }
    assert got == expected


FULL_EVIDENCE = ("bud_file_control", "bud_inyear_org_match", "bud_vs_inyear_del", "pss_vs_outturn")


def test_the_committed_full_scope_evidence_equals_the_build(full, repo_root, tmp_path):
    """`evidence/full/` holds the four audit tables that only a full build writes (the committed-scope
    `evidence/build/` cannot, because CI builds without the workbooks). They must equal a fresh export."""
    from ukfr.build import export_audit

    written = {p.name: p for p in export_audit(full, tmp_path)}
    for name in FULL_EVIDENCE:
        committed = (repo_root / "evidence" / "full" / f"{name}.csv").read_bytes().replace(b"\r\n", b"\n")
        assert committed == written[f"{name}.csv"].read_bytes(), f"{name}.csv differs: rerun the full build and copy it"
