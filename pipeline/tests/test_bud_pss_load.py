"""The BUD and PSS load: readers, row classification, and the independent recomputation.

None of these needs the real workbooks or a database, except the ones marked `localdata` and `db`.
"""

from __future__ import annotations

import ast
import csv
import inspect
from decimal import Decimal
from pathlib import Path

import pytest
from test_oscar_bud import ROWS, xlsx_bytes
from xlsx_fixture import write_xlsx

from ukfr.controls import bud_independent as independent
from ukfr.readers.oscar_bud import BUD_COLUMNS, BudRow
from ukfr.readers.pss import PSS_COLUMNS, PssFile, PssFormatError, PssStats, read_pss
from ukfr.stages import oscar_bud as bud_stage
from ukfr.stages import pss as pss_stage

# Two rows of PSS_Database_2026.xlsx (OGL v3.0), amounts in GBP thousands.
PSS_ROWS = [
    ["2021-22", "CAPITAL", "FINANCIAL TRANSACTIONS", "AME", "DEPT AME", "Business and Trade", "S013A029",
     "S013A029-POL WORKING CAPITAL", "CAPITAL SUPPORT FOR PUBLIC CORPORATIONS", ("n", "-72000")],
    ["2021-22", "CAPITAL", "FINANCIAL TRANSACTIONS", "AME", "DEPT AME", "Business and Trade", "S013A038",
     "S013A038-BRITISH BUSINESS BANK", "NET LENDING TO THE PRIVATE SECTOR AND ABROAD", ("n", "318159")],
]  # fmt: skip


def pss_file(tmp_path: Path, rows=PSS_ROWS, header=PSS_COLUMNS) -> PssFile:
    write_xlsx(tmp_path / "pss.xlsx", {"Metadata": [["about"]], "Database": [list(header), *rows]})
    return PssFile("2026-07", "PSS_Database_2026.xlsx", "pss.xlsx", "0" * 64)


def test_pss_reader_gives_text_and_exact_amounts(tmp_path):
    stats = PssStats()
    rows = list(read_pss(pss_file(tmp_path), tmp_path, stats))
    assert stats.data_rows == 2 and stats.blank_rows == 0 and "Database" in stats.sheets
    assert [r.amount for r in rows] == [Decimal("-72000"), Decimal("318159")]
    assert rows[0].line == 2 and rows[0].values[0] == "2021-22" and rows[0].values[-1] == "-72000"
    assert rows[1].values[5] == "Business and Trade"


def test_pss_reader_counts_blank_rows_and_rejects_a_wrong_header(tmp_path):
    stats = PssStats()
    assert len(list(read_pss(pss_file(tmp_path, [PSS_ROWS[0], [None] * 10, PSS_ROWS[1]]), tmp_path, stats))) == 2
    assert stats.blank_rows == 1 and stats.total_rows == 3
    bad = list(PSS_COLUMNS)
    bad[-1] = "Value"
    with pytest.raises(PssFormatError, match="header is not the PSS layout"):
        list(read_pss(pss_file(tmp_path, header=bad), tmp_path))


def test_pss_classify():
    from ukfr.readers.pss import PssRow

    ok = PssRow(2, ("2021-22",) * 9 + ("5",), Decimal("5"))
    assert pss_stage.classify(ok) is None
    assert pss_stage.classify(PssRow(2, ("x",) * 10, None))[0] == "amount_blank"
    assert pss_stage.classify(PssRow(2, ("x",) * 10, Decimal("0.12345678901")))[0] == "amount_scale"
    assert pss_stage.classify(PssRow(2, ("x",) * 10, Decimal(10) ** 28))[0] == "amount_range"
    assert len(pss_stage.RAW_COLUMNS) == 2 + 9 + 2


def make_bud_row(amount) -> BudRow:
    values = {c: "" for c in BUD_COLUMNS}
    values.update({k: str(v) for k, v in ROWS[0].items() if k != "AMOUNT"})
    values["AMOUNT"] = str(amount)
    return BudRow("2025-11", 2, values, None if amount is None else Decimal(str(amount)), "number_integral")


def test_bud_classify_and_tuple_shape():
    assert bud_stage.classify(make_bud_row(-15260)) is None
    assert bud_stage.classify(make_bud_row(None))[0] == "amount_blank"
    assert bud_stage.classify(make_bud_row("0.12345678901"))[0] == "amount_scale"
    assert bud_stage.classify(make_bud_row(10**28))[0] == "amount_range"
    t = bud_stage.raw_tuple(7, make_bud_row(-15260))
    assert len(t) == len(bud_stage.RAW_COLUMNS) == 3 + 90 + 2
    assert t[:3] == (7, 2, "2025-11") and t[-2:] == ("-15260", Decimal("-15260"))
    q = bud_stage.quarantine_tuple(7, make_bud_row(None), "amount_blank", "x")
    assert len(q) == len(bud_stage.QUARANTINE_COLUMNS)


def test_the_raw_columns_are_the_sheet_columns_in_order():
    assert bud_stage.RAW_COLUMNS[3:-2] == tuple(c.lower() for c in BUD_COLUMNS if c != "AMOUNT")


# -- the independent recomputation ------------------------------------------------------------------


def test_the_independent_module_imports_nothing_from_the_readers():
    tree = ast.parse(inspect.getsource(independent))
    imported = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported += [a.name for a in node.names]
        elif isinstance(node, ast.ImportFrom):
            imported.append(("." * node.level) + (node.module or ""))
    assert not [m for m in imported if m.startswith(".") or m.split(".")[0] == "ukfr"], imported


def test_the_independent_recomputation_on_a_small_workbook(tmp_path, monkeypatch):
    closed = {**ROWS[0], "STATUS_CODE": "Closed", "AMOUNT": 100}
    rows = [ROWS[0], ROWS[1], closed]
    body = [[r.get(c, "") for c in BUD_COLUMNS] for r in rows]
    data = [list(BUD_COLUMNS), body[0], [""] * len(BUD_COLUMNS), *body[1:]]
    folder = tmp_path / "oscar_annual_bud" / "2025-11"
    folder.mkdir(parents=True)
    (folder / "BUD_24-25.xlsx").write_bytes(xlsx_bytes([("Transparency_report_BUD_REPORTI", data), ("Sheet1", [])]))
    (folder / "Understanding_OSCAR_Data_Release_2025.docx").write_bytes(b"not a workbook")
    monkeypatch.setenv("UKFR_DATA_DIR", str(tmp_path))
    (row,) = independent.bud_rows(tmp_path)
    vintage, name, _sha, year, total, blank, data_rows, closed_rows, everything, excluding, closed_sum = row
    assert (vintage, name, year) == ("2025-11", "BUD_24-25.xlsx", "2024-25")
    assert (total, blank, data_rows, closed_rows) == ("4", "1", "3", "1")
    assert (everything, excluding, closed_sum) == ("-30988", "-31088", "100")


def test_the_independent_pss_recomputation(tmp_path, monkeypatch):
    folder = tmp_path / "pss" / "2026-07"
    folder.mkdir(parents=True)
    rows = [[c[1] if isinstance(c, tuple) else c for c in r] for r in PSS_ROWS]
    (folder / "PSS_Database_2026.xlsx").write_bytes(
        xlsx_bytes(
            [("Database", [list(PSS_COLUMNS), *[[int(c) if i == 9 else c for i, c in enumerate(r)] for r in rows]])]
        )
    )
    monkeypatch.setenv("UKFR_DATA_DIR", str(tmp_path))
    assert independent.pss_rows(tmp_path) == [["PSS_Database_2026.xlsx", "Database", "2021-22", "2", "246159"]]


def committed(repo_root, rel: Path) -> list[dict[str, str]]:
    with open(repo_root / rel, encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def test_the_committed_independent_files_have_no_local_paths(repo_root):
    for rel in (independent.BUD_OUTPUT, independent.PSS_OUTPUT):
        text = (repo_root / rel).read_text(encoding="utf-8")
        assert "\\" not in text and ":/" not in text and "Users" not in text
    assert len(committed(repo_root, independent.BUD_OUTPUT)) == 15
    assert len(committed(repo_root, independent.PSS_OUTPUT)) == 5


@pytest.mark.localdata
def test_the_recomputation_reproduces_the_committed_files(repo_root, tmp_path):
    out = independent.run_bud(repo_root, tmp_path / "bud.csv")
    assert out.read_bytes().decode("utf-8") == (repo_root / independent.BUD_OUTPUT).read_text(encoding="utf-8").replace(
        "\r\n", "\n"
    )
    out = independent.run_pss(repo_root, tmp_path / "pss.csv")
    assert out.read_bytes().decode("utf-8") == (repo_root / independent.PSS_OUTPUT).read_text(encoding="utf-8").replace(
        "\r\n", "\n"
    )
