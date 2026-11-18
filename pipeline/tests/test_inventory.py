"""The assertion inventory is generated from the files and the reconciliation document carries it."""

from __future__ import annotations

from ukfr import inventory, sqlrunner


def test_every_sql_test_has_a_header_and_is_listed_exactly_once(repo_root):
    files = sqlrunner.collect_test_files(repo_root / "sql")
    listed, problems = inventory.sql_assertions(repo_root)
    assert files, "no SQL tests found"
    assert problems == []
    assert [a.name for a in listed] == [p.stem for p in files]
    assert all(a.proves for a in listed)


def test_every_assertion_has_a_scope_and_a_place_it_runs(repo_root):
    listed, _ = inventory.sql_assertions(repo_root)
    py = inventory.python_assertions(repo_root)
    assert {a.scope for a in listed} <= {"committed", "full"}
    assert {a.scope for a in py} <= {"committed", "full"}
    for a in listed:
        if a.marker == "localdata" or a.marker.startswith("requires"):
            assert a.scope == "full", a.name
    assert any(a.scope == "committed" for a in listed) and any(a.scope == "full" for a in listed)
    assert py, "no Python test that reads the database was found"


def test_a_sql_test_without_a_header_is_reported(tmp_path):
    tests = tmp_path / "sql" / "tests"
    tests.mkdir(parents=True)
    (tests / "001_has_header.sql").write_text("-- test: something holds\nSELECT 1 WHERE 1 = 0;\n", encoding="utf-8")
    (tests / "002_no_header.sql").write_text("SELECT 1 WHERE 1 = 0;\n", encoding="utf-8")
    _, problems = inventory.sql_assertions(tmp_path)
    assert len(problems) == 1 and "002_no_header.sql" in problems[0]


def test_the_reconciliation_document_carries_the_current_inventory(repo_root):
    """Fails when a test was added, renamed or re-scoped without `ukfr inventory --write`."""
    assert inventory.problems(repo_root) == []


def _copy_inputs(repo_root, dest):
    import shutil

    for rel in ("sql", "pipeline/tests", "evidence", "data/audit"):
        shutil.copytree(repo_root / rel, dest / rel, ignore=shutil.ignore_patterns("__pycache__"))


def test_the_inventory_does_not_depend_on_files_a_full_build_leaves_in_evidence_build(repo_root, tmp_path):
    """A full-scope build writes the full-only audit tables into evidence/build as well. The inventory (and so
    the generated block of docs/reconciliation.md) must be the same with or without them."""
    _copy_inputs(repo_root, tmp_path)
    before = inventory.render_markdown(tmp_path)
    for table in ("bud_file_control", "pss_vs_outturn", "current_structure_holdout", "sr_group_bridge_vs_bud"):
        (tmp_path / "evidence" / "build" / f"{table}.csv").write_text("a,b\n1,2\n", encoding="utf-8")
    (tmp_path / "evidence" / "build" / "plan_coverage.csv").write_text("changed\n", encoding="utf-8")
    assert inventory.render_markdown(tmp_path) == before
    # and it does not need the committed copies of the full-only tables either
    (tmp_path / "evidence" / "full" / "pss_vs_outturn.csv").unlink()
    assert inventory.render_markdown(tmp_path) == before


def test_every_evidence_file_the_inventory_names_is_committed(repo_root):
    named = set()
    for a in [*inventory.sql_assertions(repo_root)[0], *inventory.python_assertions(repo_root)]:
        named |= {e.strip() for e in a.evidence.split(",") if e.strip().endswith(".csv")}
    assert named
    missing = sorted(n for n in named if not (repo_root / n).is_file())
    assert missing == []
