"""The TAC source: its manifest entry, stage, row checks and the independent control."""

from __future__ import annotations

import ast
import csv
import inspect
from decimal import Decimal

import pytest

from ukfr.config import load_settings
from ukfr.controls import tac_independent
from ukfr.discover import release_label
from ukfr.manifest import read_rows
from ukfr.readers.tac import TacRow, list_tac_files
from ukfr.stages import all_stages
from ukfr.stages import tac as stage


def row(value, text=None):
    return TacRow(2, ("A", "TAC02 SoCI", "1", "A02CY01", "12", "SCI0100A", text or str(value)), value)


def test_the_stage_is_registered_with_scope_full():
    found = {s.name: s for s in all_stages()}
    assert found["tac"].scope == "full"


@pytest.mark.parametrize(
    ("value", "reason"),
    [
        (None, "value_blank"),
        (Decimal("1.12345678901"), "value_scale"),
        (Decimal(10) ** 28, "value_range"),
        (Decimal("-9673.77933"), None),
        (Decimal("0"), None),
    ],
)
def test_classify_rejects_what_the_landing_column_cannot_hold(value, reason):
    verdict = stage.classify(row(value))
    assert (verdict[0] if verdict else None) == reason


def test_every_tac_file_in_the_manifest_gets_its_release_from_a_discovery_rule(repo_root):
    source = load_settings(repo_root).source("tac")
    assert [d.kind for d in source.discover] == ["html_index"] * 4
    rows = [r for r in read_rows(repo_root / "data" / "manifest" / "files.csv") if r.source_id == "tac"]
    assert len(rows) == 18
    for r in rows:
        labels = {release_label(d.release, title="", path="", filename=r.filename) for d in source.discover}
        assert r.release in labels, (r.filename, labels)
    assert sorted({r.release for r in rows}) == ["2019-20", "2020-21", "2021-22", "2022-23", "2023-24", "2024-25"]


def test_the_manifest_lists_two_data_files_and_one_form_per_year(repo_root):
    files = list_tac_files(repo_root)
    by_year: dict[str, list[tuple[str, str]]] = {}
    for f in files:
        by_year.setdefault(f.release, []).append((f.kind, f.provider_type))
    assert len(by_year) == 6
    for year, kinds in by_year.items():
        assert sorted(kinds) == [
            ("data", "NHS foundation trust"),
            ("data", "NHS trust"),
            ("template", ""),
        ], year


def test_the_independent_module_imports_nothing_from_the_readers():
    tree = ast.parse(inspect.getsource(tac_independent))
    imported = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported += [a.name for a in node.names]
        elif isinstance(node, ast.ImportFrom):
            imported.append(("." * node.level) + (node.module or ""))
    assert not [m for m in imported if m.startswith(".") or m.split(".")[0] == "ukfr"], imported


def committed(repo_root) -> list[dict[str, str]]:
    with open(repo_root / tac_independent.OUTPUT, encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def test_the_committed_control_covers_every_worksheet_of_every_data_file(repo_root):
    rows = committed(repo_root)
    files = {r["filename"] for r in rows}
    assert len(files) == 12
    for f in files:
        sheets = {r["worksheet"] for r in rows if r["filename"] == f}
        assert {"TAC02 SoCI", "TAC03 SoFP", "TAC05 SoCF"} <= sheets
        assert len(sheets) in (28, 29)


@pytest.mark.localdata
def test_the_recomputation_reproduces_the_committed_file(repo_root, tmp_path):
    out = tmp_path / "again.csv"
    tac_independent.run(repo_root, out)
    assert out.read_bytes().decode("utf-8") == (repo_root / tac_independent.OUTPUT).read_bytes().decode(
        "utf-8"
    ).replace("\r\n", "\n")


@pytest.mark.db
@pytest.mark.localdata
def test_the_loaded_values_agree_with_the_independent_recomputation(db, repo_root):
    expected = {(r["filename"], r["worksheet"]): r for r in committed(repo_root)}
    loaded = {
        (r[0], r[1]): r
        for r in db.query(
            "SELECT f.filename, w.worksheet_name, w.data_rows, ISNULL(a.n, 0), a.s "
            "FROM raw.tac_worksheet AS w JOIN raw.tac_file AS f ON f.file_id = w.file_id "
            "LEFT JOIN (SELECT file_id, worksheet_name, COUNT_BIG(*) AS n, SUM(value) AS s "
            "           FROM raw.tac_value GROUP BY file_id, worksheet_name) AS a "
            "  ON a.file_id = w.file_id AND a.worksheet_name = w.worksheet_name"
        )
    }
    assert set(loaded) == set(expected)
    statement_sheets = 0
    for key, r in expected.items():
        _, _, rows_read, rows_loaded, total = loaded[key]
        assert int(r["data_rows"]) == rows_read, key
        if key[1][:5] in ("TAC02", "TAC03", "TAC05"):
            statement_sheets += 1
            assert rows_loaded == rows_read, key
            assert Decimal(total) == Decimal(r["value_sum"]), key
        else:
            assert rows_loaded == 0, key
    assert statement_sheets == 36
