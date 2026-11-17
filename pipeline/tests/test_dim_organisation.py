"""The organisation and department dimensions: the named reorganisations, and the 23 bodies that moved.

Every test reads the database that `ukfr build` has filled. A case asks, for a release before and a release
after an event, which durable key, department and version a code resolves to, through
`dw.organisation_release_map` (the table the fact will join on).
"""

from __future__ import annotations

import csv

import pytest

pytestmark = pytest.mark.db

RESOLVE = """
SELECT m.durable_key, o.organisation_code, o.organisation_name, d.department_number, d.department_name,
       o.valid_from_release, o.valid_to_release, o.successor_durable_key
FROM dw.organisation_release_map AS m
JOIN dw.dim_organisation AS o ON o.organisation_key = m.organisation_key
JOIN dw.dim_department AS d ON d.department_key = m.department_key
WHERE m.organisation_code = ? AND m.release = ?
"""


def resolve(db, code, release):
    rows = db.query(RESOLVE, (code, release))
    assert len(rows) == 1, f"{code} in {release}: {len(rows)} rows in the release map"
    key, version_code, name, number, dept, vfrom, vto, successor = rows[0]
    return {
        "key": key,
        "version_code": version_code,
        "name": name,
        "dept_number": number,
        "dept": dept,
        "from": vfrom,
        "to": vto,
        "successor": successor,
    }


def absent(db, code, release):
    count = db.scalar(
        "SELECT COUNT(*) FROM dw.organisation_release_map WHERE organisation_code = ? AND release = ?", (code, release)
    )
    return count == 0


def test_beis_core_becomes_dsit_core_under_the_same_code_without_merging_history(db):
    before, after = resolve(db, "BIS084", "2023-06"), resolve(db, "BIS084", "2023-09")
    assert (before["key"], before["dept_number"], before["dept"]) == (
        "BIS.BEIS",
        "084",
        "Department for Business, Energy and Industrial Strategy",
    )
    assert before["name"] == "Department for Business, Energy and Industrial Strategy"
    assert (after["key"], after["dept_number"], after["dept"]) == (
        "BIS.DSIT",
        "084",
        "Department for Science, Innovation and Technology",
    )
    assert before["to"] == "2023-06" and after["from"] == "2023-09"


def test_dit_core_becomes_dbt_core_under_the_same_code_without_merging_history(db):
    before, after = resolve(db, "UKT013", "2023-06"), resolve(db, "UKT013", "2023-09")
    assert (before["key"], before["dept_number"], before["dept"]) == (
        "UKT.DIT",
        "013",
        "Department for International Trade",
    )
    assert (after["key"], after["dept_number"], after["dept"]) == (
        "UKT.DBT",
        "013",
        "Department for Business and Trade",
    )
    assert before["to"] == "2023-06" and after["from"] == "2023-09"


def test_dfid_core_becomes_fcdo_core_when_the_code_is_renamed_and_the_department_label_follows_later(db):
    before = resolve(db, "DID030", "2020-09")
    renamed = resolve(db, "DID030", "2020-12")
    after = resolve(db, "DID030", "2021-09")
    assert (before["key"], before["dept"]) == ("DID.DFID", "Department for International Development")
    # The organisation row is renamed in 2020-12 while the files still label the department DFID.
    assert (renamed["key"], renamed["dept"]) == ("DID.FCDO", "Department for International Development")
    assert (after["key"], after["dept"]) == ("DID.FCDO", "Foreign, Commonwealth and Development Office")
    assert before["to"] == "2020-09" and renamed["from"] == "2020-12"


def test_fco_core_merges_into_fcdo_core(db):
    before = resolve(db, "FCO027", "2021-03")
    last = resolve(db, "FCO027", "2021-06")
    after = resolve(db, "DID030", "2021-09")
    assert (before["key"], before["dept_number"], before["dept"]) == (
        "FCO",
        "027",
        "Foreign and Commonwealth Office",
    )
    assert before["successor"] == "DID.FCDO" and last["to"] == "2021-06"
    assert absent(db, "FCO027", "2021-09")
    assert (after["key"], after["dept_number"]) == ("DID.FCDO", "030")
    assert before["key"] != after["key"]  # two codes reported together from 2020-12 cannot share a key


def test_ofcom_keeps_one_durable_key_across_its_prefix_change(db):
    before, after = resolve(db, "OFC048", "2023-06"), resolve(db, "OCM084", "2023-12")
    assert before["key"] == after["key"] == "OFC"
    assert before["dept_number"] == "048" and after["dept_number"] == "084"
    assert after["dept"] == "Department for Science, Innovation and Technology"
    assert (before["version_code"], after["version_code"]) == ("OFC048", "OCM084")
    assert db.scalar("SELECT COUNT(DISTINCT organisation_key) FROM dw.dim_organisation WHERE durable_key = 'OFC'") == 2


def test_ukg_prefix_is_split_into_two_bodies_and_the_renamed_green_investment_body_follows_its_department(db):
    green_before = resolve(db, "UKG084", "2023-06")
    treasury = resolve(db, "UKG087", "2023-06")
    green_after = resolve(db, "UKG066", "2024-06")
    treasury_after = resolve(db, "UKG087", "2024-06")
    assert green_before["key"] == green_after["key"] == "UKG084"
    assert treasury["key"] == treasury_after["key"] == "UKG087"
    assert green_before["key"] != treasury["key"]
    assert (green_before["dept_number"], green_after["dept_number"]) == ("084", "066")
    assert green_after["dept"] == "Department for Energy Security and Net Zero"
    assert treasury["dept"] == "HM Treasury"


def test_doh_prefix_is_split_into_the_nhs_line_and_the_transport_line(db):
    assert absent(db, "DOH004", "2019-12")
    nhs_before = resolve(db, "DOH033", "2019-12")
    transport = resolve(db, "DOH004", "2020-12")
    nhs_during = resolve(db, "DOH033", "2020-12")
    nhs_after = resolve(db, "DOH033", "2021-06")
    assert absent(db, "DOH004", "2021-06")
    assert transport["key"] == "DOH004" and transport["dept"] == "Department for Transport"
    assert nhs_before["key"] == nhs_during["key"] == nhs_after["key"] == "DOH033"
    assert nhs_during["dept"] == "Department of Health and Social Care"


def test_ehr_coding_error_in_june_2019_is_one_body_with_one_version_per_release(db):
    first = resolve(db, "EHR034", "2019-03")
    twin = resolve(db, "EHR030", "2019-06")
    same_release = resolve(db, "EHR034", "2019-06")
    settled = resolve(db, "EHR010", "2020-06")
    assert first["key"] == twin["key"] == same_release["key"] == settled["key"] == "EHR"
    # The coding error is mapped to the version of the code it duplicates, but keeps its own department.
    organisation_keys = db.query(
        "SELECT organisation_code, organisation_key, department_key FROM dw.organisation_release_map "
        "WHERE release = '2019-06' AND organisation_code IN ('EHR030', 'EHR034') ORDER BY organisation_code"
    )
    assert organisation_keys[0][1] == organisation_keys[1][1]
    assert organisation_keys[0][2] != organisation_keys[1][2]
    assert twin["version_code"] == "EHR034"
    assert (twin["dept"], settled["dept"]) == ("Department for International Development", "Cabinet Office")


def test_the_unknown_members_exist_and_nothing_real_uses_them(db):
    organisation = "SELECT COUNT(*) FROM dw.dim_organisation WHERE organisation_key = -1 AND department_key = -1"
    department = "SELECT COUNT(*) FROM dw.dim_department WHERE department_key = -1 AND member_type = 'Unknown'"
    used = "SELECT COUNT(*) FROM dw.organisation_release_map WHERE organisation_key = -1 OR department_key = -1"
    assert (db.scalar(organisation), db.scalar(department), db.scalar(used)) == (1, 1, 0)


def test_an_alias_flip_does_not_start_a_version_but_a_real_rename_does(db):
    # UK Export Finance is published as ECGD and as UK Export Finance in alternating releases: one version.
    assert db.scalar("SELECT COUNT(*) FROM dw.dim_organisation WHERE durable_key = 'ECG'") == 1
    # Parliament Restoration and Renewal became the Parliamentary Works Grant once, in 2023-09.
    rows = db.query(
        "SELECT organisation_name, valid_from_release, valid_to_release, version_reason FROM dw.dim_organisation "
        "WHERE durable_key = 'PRR' ORDER BY version_no"
    )
    assert [r[0] for r in rows] == ["Parliament: Restoration and Renewal", "Parliamentary Works Grant"]
    assert rows[1][1] == "2023-09" and "name change" in rows[1][3]


def test_the_23_bodies_that_moved_department_and_kept_their_prefix_keep_one_durable_key(db, repo_root):
    path = repo_root / "docs" / "profiling" / "data" / "org_durable_key_candidates.csv"
    with path.open(encoding="utf-8", newline="") as fh:
        rows = [r for r in csv.DictReader(fh) if r["finding"] == "b0_suffix_change"]
    by_prefix: dict[str, set[str]] = {}
    for r in rows:
        by_prefix.setdefault(r["prefix"], set()).add(r["organisation_code"])
    assert len(rows) == 46 and len(by_prefix) == 23
    for prefix, codes in sorted(by_prefix.items()):
        assert len(codes) == 2, prefix
        keys = db.query(
            "SELECT DISTINCT m.durable_key FROM dw.organisation_release_map m WHERE m.organisation_code IN (?, ?)",
            tuple(sorted(codes)),
        )
        assert [k[0] for k in keys] == [prefix], f"{prefix}: {codes} resolve to {keys}"
        versions = db.query(
            "SELECT organisation_code FROM dw.dim_organisation WHERE durable_key = ? ORDER BY version_no", (prefix,)
        )
        merged = {
            r[0]
            for r in db.query(
                "SELECT DISTINCT organisation_code FROM stg.organisation_release_key WHERE is_merged_code = 1"
            )
        }
        # A code that only duplicates another in one release (EHR030) rides on the other code's version.
        assert codes - merged <= {v[0] for v in versions}, f"{prefix}: a code has no version of its own"
