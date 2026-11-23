"""The DAX test framework: pairing of tests and expected values, the comparison, and the committed results."""

from __future__ import annotations

import csv
import shutil
from decimal import Decimal
from pathlib import Path

import pytest

from ukfr import cli, modeltests
from ukfr.config import data_dir


def _write(path: Path, header: list[str], rows: list[list[str]]) -> None:
    modeltests.write_csv_plain(path, header, rows)


def _tables(expected_rows: list[list[str]], result_rows: list[list[str]], header=("name", "total")):
    return (list(header), expected_rows), (list(header), result_rows)


# ------------------------------------------------------------------------------------------ pairing
def test_every_dax_test_has_an_expected_source_and_every_expected_source_has_a_dax_test(repo_root):
    assert modeltests.check_pairs(repo_root) == []


def test_there_is_at_least_one_test_and_the_numbers_are_unique(repo_root):
    stems = [p.stem for p in modeltests.dax_tests(repo_root)]
    assert stems, "no tests/dax/*.dax"
    assert len({s[:3] for s in stems}) == len(stems)


def test_expected_sql_reads_dw_base_tables_and_never_the_model_views(repo_root):
    """The expected values are independent of the view layer the model reads."""
    for stem, path in modeltests.expected_sources(repo_root).items():
        if path.suffix == ".sql":
            text = path.read_text(encoding="utf-8").lower()
            assert "v_model_" not in text, f"{stem}: expected SQL must not read dw.v_model_* views"
            assert "dw." in text or "audit." in text, f"{stem}: expected SQL reads no warehouse table"


def test_a_dax_test_without_its_expected_source_is_reported(tmp_path):
    (tmp_path / "tests" / "dax").mkdir(parents=True)
    (tmp_path / "tests" / "expected").mkdir(parents=True)
    (tmp_path / "tests" / "dax" / "900_lonely.dax").write_text('EVALUATE ROW("a", 1)', encoding="utf-8")
    (tmp_path / "tests" / "expected" / "901_orphan.sql").write_text("SELECT 1 AS a", encoding="utf-8")
    problems = modeltests.check_pairs(tmp_path)
    assert any("900_lonely.dax has no tests/expected/900_lonely.sql" in p for p in problems)
    assert any("901_orphan.sql has no tests/dax/901_orphan.dax" in p for p in problems)


def test_a_badly_named_dax_test_is_reported(tmp_path):
    (tmp_path / "tests" / "dax").mkdir(parents=True)
    (tmp_path / "tests" / "expected").mkdir(parents=True)
    (tmp_path / "tests" / "dax" / "9_short.dax").write_text("x", encoding="utf-8")
    assert any("must be <three digits>" in p for p in modeltests.check_pairs(tmp_path))


# ---------------------------------------------------------------------------------------- comparison
def test_equal_tables_pass_whatever_the_row_order():
    o = modeltests.compare_tables(*_tables([["a", "1.5"], ["b", "2"]], [["b", "2.0000"], ["a", "1.5"]]))
    assert o.ok, o.details
    assert Decimal(o.max_abs_diff) == 0


def test_the_tolerance_is_one_unit_of_the_fourth_decimal():
    ok = modeltests.compare_tables(*_tables([["a", "10.0000"]], [["a", "10.0001"]]))
    assert ok.ok and Decimal(ok.max_abs_diff) == Decimal("0.0001")
    bad = modeltests.compare_tables(*_tables([["a", "10.0000"]], [["a", "10.0002"]]))
    assert not bad.ok and Decimal(bad.max_abs_diff) == Decimal("0.0002")


def test_a_wrong_number_a_wrong_text_a_missing_row_and_different_columns_each_fail():
    assert not modeltests.compare_tables(*_tables([["a", "1"]], [["a", "2"]])).ok
    assert not modeltests.compare_tables(*_tables([["a", "1"]], [["b", "1"]])).ok
    assert not modeltests.compare_tables(*_tables([["a", "1"], ["b", "2"]], [["a", "1"]])).ok
    assert not modeltests.compare_tables((["x", "total"], [["a", "1"]]), (["name", "total"], [["a", "1"]])).ok


def test_blank_equals_blank_and_a_blank_is_not_zero():
    assert modeltests.compare_tables(*_tables([["a", ""]], [["a", ""]])).ok
    assert not modeltests.compare_tables(*_tables([["a", ""]], [["a", "0"]])).ok


def test_booleans_match_whatever_their_case():
    assert modeltests.compare_tables(*_tables([["a", "True"]], [["a", "true"]])).ok
    assert not modeltests.compare_tables(*_tables([["a", "True"]], [["a", "false"]])).ok


def test_dscmd_column_names_lose_their_brackets():
    assert modeltests.normalise_header("[release]") == "release"
    assert modeltests.normalise_header("Release[Release Label]") == "Release Label"
    assert modeltests.normalise_header('"[x]"'.strip('"')) == "x"
    assert modeltests.normalise_header("plain") == "plain"


def test_a_float_in_an_expected_result_is_refused():
    with pytest.raises(modeltests.ModelTestError):
        modeltests.format_cell(1.5)


def _mini_project(tmp_path, expected_value: str, result_value: str | None):
    root = tmp_path / "repo"
    (root / "tests" / "dax").mkdir(parents=True)
    (root / "tests" / "expected").mkdir(parents=True)
    (root / "tests" / "dax" / "900_mini.dax").write_text('EVALUATE ROW("name", "a", "total", 1)', encoding="utf-8")
    (root / "tests" / "expected" / "900_mini.sql").write_text(
        "SELECT 'a' AS name, 1 AS total FROM dw.x", encoding="utf-8"
    )
    exp = tmp_path / "expected"
    res = tmp_path / "results"
    _write(exp / "900_mini.csv", ["name", "total"], [["a", expected_value]])
    _write(exp / "_meta.csv", ["key", "value"], [["build_scope", "full"]])
    if result_value is not None:
        _write(res / "900_mini.csv", ["name", "total"], [["a", result_value]])
    return root, exp, res


def test_dax_compare_exits_non_zero_on_a_wrong_expected_value_and_zero_on_a_right_one(tmp_path, monkeypatch, capsys):
    root, exp, res = _mini_project(tmp_path, "1", "1")
    monkeypatch.setenv("UKFR_REPO_ROOT", str(root))
    args = [
        "dax-compare",
        "--expected-dir",
        str(exp),
        "--results-dir",
        str(res),
        "--evidence",
        str(tmp_path / "ev.csv"),
    ]
    assert cli.main(args) == 0
    assert "PASS" in capsys.readouterr().out
    _write(exp / "900_mini.csv", ["name", "total"], [["a", "999"]])
    capsys.readouterr()
    assert cli.main(args) == 1
    out = capsys.readouterr().out
    assert "FAIL" in out and "expected 999" in out


def test_dax_compare_reports_a_missing_result_and_a_missing_expected_file(tmp_path):
    root, exp, res = _mini_project(tmp_path, "1", None)
    (o,) = modeltests.compare_all(root, exp, res)
    assert o.status == "missing_result" and not o.ok
    (exp / "900_mini.csv").unlink()
    (o,) = modeltests.compare_all(root, exp, res)
    assert o.status == "missing_expected" and not o.ok


def test_the_evidence_file_has_no_timestamps_and_one_row_per_test(tmp_path):
    root, exp, res = _mini_project(tmp_path, "1", "1")
    outcomes = modeltests.compare_all(root, exp, res)
    out = tmp_path / "ev.csv"
    modeltests.write_evidence(out, outcomes, "full")
    with out.open(encoding="utf-8", newline="") as fh:
        rows = list(csv.DictReader(fh))
    assert [r["test_id"] for r in rows] == ["900"]
    assert rows[0]["status"] == "pass" and rows[0]["build_scope"] == "full"
    assert list(rows[0]) == modeltests.EVIDENCE_HEADER
    assert b"\r" not in out.read_bytes()


# ------------------------------------------------------------------------- the committed expected, results
def test_the_committed_results_equal_the_committed_expected_values_and_the_evidence_says_so(repo_root):
    """Offline: the results the model gave (committed) agree with the expected values (committed)."""
    outcomes = modeltests.compare_all(repo_root)
    bad = [(o.stem, o.status, o.details) for o in outcomes if not o.ok]
    assert not bad, bad
    with (repo_root / modeltests.EVIDENCE_CSV).open(encoding="utf-8", newline="") as fh:
        evidence = {r["test_id"] + "_" + r["test_name"]: r for r in csv.DictReader(fh)}
    assert set(evidence) == {p.stem for p in modeltests.dax_tests(repo_root)}
    assert {r["status"] for r in evidence.values()} == {"pass"}


def test_the_expected_files_record_the_build_scope_they_came_from(repo_root):
    assert modeltests.read_scope(repo_root / modeltests.EXPECTED_DIR) in ("committed", "full")


# ------------------------------------------------------------------------------- generating expected values
@pytest.mark.db
def test_every_expected_sql_runs_and_agrees_with_the_committed_file_when_the_scope_is_the_same(db, repo_root, tmp_path):
    from ukfr import real_totals

    scope = real_totals.build_scope(db)
    same_scope = modeltests.read_scope(repo_root / modeltests.EXPECTED_DIR) == scope
    ran = 0
    for stem, src in modeltests.expected_sources(repo_root).items():
        if src.suffix != ".sql" or modeltests.unmet_requirements(db, src):
            continue
        header, rows = modeltests.generate_one(repo_root, db, src)
        assert header and len(set(header)) == len(header), stem
        out = tmp_path / f"{stem}.csv"
        modeltests.write_csv(out, header, rows)
        ran += 1
        if same_scope:
            committed = (repo_root / modeltests.EXPECTED_DIR / f"{stem}.csv").read_bytes()
            assert out.read_bytes() == committed, f"{stem}: regenerated expected values differ from the committed file"
    assert ran >= 3


@pytest.mark.db
@pytest.mark.localdata
def test_ukfr_expected_is_deterministic_and_writes_the_scope(db, repo_root, tmp_path):
    if not (data_dir(repo_root) / "gdp_deflator").is_dir():
        pytest.skip("the pinned deflator files are not under UKFR_DATA_DIR")
    from ukfr import real_totals

    scope = real_totals.build_scope(db)
    a, b = tmp_path / "a", tmp_path / "b"
    modeltests.write_expected(repo_root, db, scope, out_dir=a)
    modeltests.write_expected(repo_root, db, scope, out_dir=b)
    names = sorted(p.name for p in a.iterdir())
    assert names == sorted(p.name for p in b.iterdir())
    for n in names:
        assert (a / n).read_bytes() == (b / n).read_bytes(), n
    assert modeltests.read_scope(a) == scope
    shutil.rmtree(a)
