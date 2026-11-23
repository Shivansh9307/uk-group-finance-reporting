"""The real-versus-derived register in README.md covers every authored file, and one path loads each of them."""

from __future__ import annotations

import csv
import re

import pytest

from ukfr.stages import all_stages
from ukfr.stages.authored import list_authored_files
from ukfr.stages.synthetic import list_synthetic_files

HEADING = "## Register of real, authored, derived and synthetic data"
# | `authored/<name>.csv` | class | `schema.table` | rows | what it holds | reach | test |
REGISTER_ROW = re.compile(r"^\|\s*`authored/([a-z0-9_]+)\.csv`\s*\|(.*)\|\s*$")
# | `synthetic/<name>.csv` | synthetic | `synthetic.<name>` | rows | what it holds | reach | test |
SYNTHETIC_ROW = re.compile(r"^\|\s*`synthetic/([a-z0-9_]+)\.csv`\s*\|(.*)\|\s*$")
# The synthetic tables that exist, and the only two objects that read them (both views of the model's security tables).
SYNTHETIC_TABLES = {"synthetic.user_department"}
SYNTHETIC_READERS = {"dw.v_model_user_department", "dw.v_model_user_plan_group"}


def _block(repo_root) -> str:
    text = (repo_root / "README.md").read_text(encoding="utf-8")
    assert HEADING in text, f"README.md has no section '{HEADING}'"
    start = text.index(HEADING)
    nxt = text.find("\n## ", start + len(HEADING))
    return text[start : nxt if nxt != -1 else len(text)]


def _authored_rows(repo_root) -> dict[str, list[str]]:
    rows = {}
    for line in _block(repo_root).splitlines():
        m = REGISTER_ROW.match(line)
        if m:
            rows[m.group(1)] = [c.strip() for c in m.group(2).split("|")]
    return rows


def test_the_register_lists_every_authored_file_with_its_row_count_and_no_reach_to_a_real_total(repo_root):
    register = _authored_rows(repo_root)
    files = {p.stem: p for p in list_authored_files(repo_root)}
    assert files, "no authored files"
    assert set(files) == set(register), (sorted(set(files) - set(register)), sorted(set(register) - set(files)))
    for stem, path in files.items():
        with path.open(encoding="utf-8-sig", newline="") as fh:
            n = sum(1 for _ in csv.reader(fh)) - 1
        cells = register[stem]
        assert cells[0] == "authored", f"{stem}: class must be authored"
        assert cells[1] == f"`authored.{stem}`", f"{stem}: schema and table must be authored.{stem}"
        assert cells[2].replace(",", "") == str(n), f"{stem}: the register says {cells[2]} rows, the file has {n}"
        assert cells[4].lower().startswith("no"), f"{stem}: an authored file never reaches a real total"
        assert cells[5].strip("`"), f"{stem}: name the test that proves it"


def test_the_register_names_the_derived_objects_the_sql_authored_table_and_the_unallocated_members(repo_root):
    block = _block(repo_root)
    for needed in (
        "`dw.plan_phasing_profile`",
        "`dw.fact_plan_phased`",
        "`authored.pss_sr_group_alias`",
        "Unallocated",
    ):
        assert needed in block, f"{needed} is missing from the register"
    for line in block.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if line.startswith("|") and len(cells) >= 7 and cells[1] in ("derived", "synthetic", "authored"):
            assert cells[5].lower().startswith("no"), f"a {cells[1]} row must say no to a real total: {line[:90]}"


def test_one_stage_loads_the_authored_files_and_no_other_stage_writes_to_the_authored_schema(repo_root):
    """The plan name map is loaded by the generic `authored` stage like every other file; the plan stage does not
    load it a second time."""
    assert [s.name for s in all_stages()].count("authored") == 1
    for module in sorted((repo_root / "pipeline" / "src" / "ukfr" / "stages").glob("*.py")):
        if module.name in ("authored.py", "__init__.py"):
            continue
        text = module.read_text(encoding="utf-8")
        assert not re.search(r"(INSERT INTO|CREATE TABLE|DELETE FROM|insert_many\(\s*[\"'])\s*authored\.", text), (
            f"{module.name} writes to the authored schema; only the authored stage does"
        )


@pytest.mark.db
def test_each_authored_file_is_one_table_with_the_rows_of_the_file(db, repo_root):
    for path in list_authored_files(repo_root):
        with path.open(encoding="utf-8-sig", newline="") as fh:
            n = sum(1 for _ in csv.reader(fh)) - 1
        got = db.scalar(f"SELECT COUNT_BIG(*) FROM authored.[{path.stem}]")
        assert got == n, f"authored.{path.stem} has {got} rows, the file has {n}"
        assert db.scalar(f"SELECT COALESCE(MAX(_load_order), 0) FROM authored.[{path.stem}]") == n
    plan_name_maps = (
        "SELECT COUNT_BIG(*) FROM sys.tables WHERE SCHEMA_NAME(schema_id) = 'authored' AND name = 'plan_name_map'"
    )
    assert db.scalar(plan_name_maps) == 1


def test_the_register_lists_every_synthetic_file_with_its_row_count_and_no_reach_to_a_real_total(repo_root):
    register = {}
    for line in _block(repo_root).splitlines():
        m = SYNTHETIC_ROW.match(line)
        if m:
            register[m.group(1)] = [c.strip() for c in m.group(2).split("|")]
    files = {p.stem: p for p in list_synthetic_files(repo_root)}
    assert set(files) == {t.split(".")[1] for t in SYNTHETIC_TABLES}, sorted(files)
    assert set(files) == set(register), (sorted(set(files) - set(register)), sorted(set(register) - set(files)))
    for stem, path in files.items():
        with path.open(encoding="utf-8-sig", newline="") as fh:
            rows = list(csv.DictReader(fh))
        cells = register[stem]
        assert cells[0] == "synthetic", f"{stem}: class must be synthetic"
        assert cells[1] == f"`synthetic.{stem}`", f"{stem}: schema and table must be synthetic.{stem}"
        assert cells[2].replace(",", "") == str(len(rows)), f"{stem}: the register says {cells[2]} rows"
        assert cells[4].lower().startswith("no"), f"{stem}: a synthetic file never reaches a real total"
        assert cells[5].strip("`"), f"{stem}: name the test that proves it"
        assert {r["data_class"] for r in rows} == {"synthetic"}, f"{stem}: every row must say synthetic"
        assert all(r["user_principal_name"].endswith("@example.org") for r in rows), "reserved domain only"


def test_the_register_names_the_model_tables_of_the_security_roles_as_synthetic(repo_root):
    block = _block(repo_root)
    for needed in ("Model table `User Department (synthetic)`", "Model table `User Plan Group (synthetic)`"):
        line = next((ln for ln in block.splitlines() if ln.startswith(f"| {needed}")), None)
        assert line, f"{needed} is missing from the register"
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        assert cells[1] == "synthetic" and cells[5].lower().startswith("no"), line[:100]


@pytest.mark.db
def test_the_synthetic_schemas_hold_exactly_the_registered_tables_and_no_fact_or_total_view_reads_them(db):
    """The synthetic and scale schemas hold the tables the register names and nothing else, and the only objects
    that read a synthetic table are the two views of the security tables, which nothing reads in turn."""
    tables = db.query(
        "SELECT SCHEMA_NAME(schema_id) + '.' + name FROM sys.tables "
        "WHERE SCHEMA_NAME(schema_id) IN ('synthetic', 'scale') ORDER BY 1"
    )
    assert {t[0] for t in tables} == SYNTHETIC_TABLES, tables
    readers = db.query(
        "SELECT DISTINCT OBJECT_SCHEMA_NAME(d.referencing_id) + '.' + OBJECT_NAME(d.referencing_id) "
        "FROM sys.sql_expression_dependencies AS d "
        "WHERE OBJECT_SCHEMA_NAME(d.referenced_id) IN ('synthetic', 'scale') "
        "AND d.referencing_id NOT IN (SELECT object_id FROM sys.check_constraints) ORDER BY 1"
    )
    assert {r[0] for r in readers} == SYNTHETIC_READERS, readers
    onward = db.query(
        "SELECT OBJECT_SCHEMA_NAME(d.referencing_id) + '.' + OBJECT_NAME(d.referencing_id) "
        "FROM sys.sql_expression_dependencies AS d WHERE d.referenced_id IN "
        "(OBJECT_ID('dw.v_model_user_department'), OBJECT_ID('dw.v_model_user_plan_group'))"
    )
    assert onward == [], onward
