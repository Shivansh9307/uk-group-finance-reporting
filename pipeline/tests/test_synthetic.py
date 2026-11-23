"""The synthetic-CSV load stage, and the proof that the invented user map never reaches a real total."""

from __future__ import annotations

import csv

import pytest

from ukfr import real_totals
from ukfr.stages import all_stages, select_stages
from ukfr.stages.authored import AuthoredFileError
from ukfr.stages.synthetic import list_synthetic_files, load_one


def test_the_stage_is_registered_with_committed_scope_and_runs_after_the_authored_stage_and_before_the_sql_loads():
    by_name = {s.name: s for s in all_stages()}
    assert by_name["synthetic"].scope == "committed"
    assert "synthetic" in [s.name for s in select_stages("committed")]
    assert by_name["authored"].order < by_name["synthetic"].order < by_name["oscar_inyear"].order


def test_a_missing_folder_means_no_files(tmp_path):
    assert list_synthetic_files(tmp_path) == []


def test_every_synthetic_file_is_an_invented_user_map_with_no_amount(repo_root):
    files = list_synthetic_files(repo_root)
    assert [p.name for p in files] == ["user_department.csv"]
    with files[0].open(encoding="utf-8-sig", newline="") as fh:
        reader = csv.DictReader(fh)
        header = reader.fieldnames or []
        rows = list(reader)
    assert header == ["user_principal_name", "department_number", "persona", "data_class", "note"]
    assert rows, "the user map is empty"
    for r in rows:
        assert r["data_class"] == "synthetic"
        assert r["user_principal_name"].endswith("@example.org"), r["user_principal_name"]
        assert len(r["department_number"]) == 3 and r["department_number"].isdigit(), r["department_number"]
    users = {r["user_principal_name"] for r in rows}
    assert "nobody@example.org" not in users, "the user the tests use as unmapped must be in no row"
    assert any(sum(1 for r in rows if r["user_principal_name"] == u) >= 2 for u in users), "no user has two departments"


class _NoTable:
    """A database that has no synthetic table."""

    def scalar(self, sql, params=()):
        return None


class _Ctx:
    def __init__(self, root):
        self.repo_root, self.db, self.scope = root, _NoTable(), "committed"

    def log(self, _):
        pass


def test_a_file_without_its_typed_table_stops_the_load_and_names_the_file(tmp_path):
    folder = tmp_path / "synthetic"
    folder.mkdir()
    path = folder / "orphan.csv"
    path.write_text("a,b\n1,2\n", encoding="utf-8")
    with pytest.raises(AuthoredFileError, match=r"orphan\.csv: there is no table synthetic\.orphan"):
        load_one(_Ctx(tmp_path), path)


@pytest.mark.db
def test_the_user_map_table_has_the_rows_of_the_file_in_file_order(db, repo_root):
    path = repo_root / "synthetic" / "user_department.csv"
    with path.open(encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.DictReader(fh))
    got = db.query(
        "SELECT _load_order, user_principal_name, department_number FROM synthetic.user_department ORDER BY _load_order"
    )
    assert [tuple(r) for r in got] == [
        (i, r["user_principal_name"], r["department_number"]) for i, r in enumerate(rows, start=1)
    ]


@pytest.mark.db
def test_the_real_facts_keep_the_pinned_row_counts_and_sums_with_the_synthetic_user_map_loaded(db, repo_root):
    """The map is present (so the pinned totals are measured with it loaded) and every real fact still has the rows and
    the sum in evidence/expected/real_fact_totals.csv. The two role views are not facts and carry no amount column."""
    assert db.scalar("SELECT COUNT_BIG(*) FROM synthetic.user_department") > 0
    scope = real_totals.build_scope(db)
    pinned = {
        r["fact"]: r for r in real_totals.read_expected(repo_root / real_totals.EXPECTED_CSV) if r["scope"] == scope
    }
    measured = {r["fact"]: r for r in real_totals.measure(db, scope)}
    assert set(measured) == set(pinned) and measured, (scope, sorted(measured), sorted(pinned))
    for fact, got in measured.items():
        assert (got["rows"], got["amount_sum"]) == (pinned[fact]["rows"], pinned[fact]["amount_sum"]), fact
    amounts = db.query(
        "SELECT OBJECT_NAME(c.object_id), c.name FROM sys.columns AS c "
        "JOIN sys.types AS t ON t.user_type_id = c.user_type_id "
        "WHERE c.object_id IN (OBJECT_ID('dw.v_model_user_department'), OBJECT_ID('dw.v_model_user_plan_group')) "
        "AND t.name IN ('decimal', 'numeric', 'float', 'real', 'money', 'smallmoney', 'bigint')"
    )
    assert amounts == [], amounts
