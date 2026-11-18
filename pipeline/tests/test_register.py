"""The real-versus-derived register in README.md covers every authored file, and one path loads each of them."""

from __future__ import annotations

import csv
import re

import pytest

from ukfr.stages import all_stages
from ukfr.stages.authored import list_authored_files

HEADING = "## Register of real, authored, derived and synthetic data"
# | `authored/<name>.csv` | class | `schema.table` | rows | what it holds | reach | test |
REGISTER_ROW = re.compile(r"^\|\s*`authored/([a-z0-9_]+)\.csv`\s*\|(.*)\|\s*$")


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


@pytest.mark.db
def test_there_is_no_synthetic_data_yet(db):
    """The register says no synthetic data exists; the `synthetic` and `scale` schemas hold no table."""
    tables = db.query(
        "SELECT SCHEMA_NAME(schema_id) + '.' + name FROM sys.tables "
        "WHERE SCHEMA_NAME(schema_id) IN ('synthetic', 'scale')"
    )
    assert tables == [], tables
