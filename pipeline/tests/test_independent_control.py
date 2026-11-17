"""The independent recomputation of the in-year file controls (it shares no code with `ukfr.readers`).

`data/audit/inyear_independent_control.csv` is committed. Two checks: running the recomputation again
gives the same bytes, and the loaded data agrees with it. CSV files must agree exactly. ODS files go
through `python-calamine`, which returns binary floats, so for them the row count must still agree
exactly while the exact sum may differ by float residue (tolerance 1e-6 in GBP thousands) and the
four-decimal sum by rounding ties that the float's short form creates (tolerance 0.01).
"""

from __future__ import annotations

import csv
from decimal import Decimal

import pytest

from ukfr.controls import inyear_independent as independent

EXACT_TOLERANCE = Decimal("0.000001")
ROUNDED_TOLERANCE = Decimal("0.01")


def committed(repo_root) -> list[dict[str, str]]:
    with open(repo_root / independent.OUTPUT, encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def test_the_recomputation_reproduces_the_committed_file(repo_root, tmp_path):
    out = tmp_path / "again.csv"
    independent.run(repo_root, out)
    assert out.read_bytes().decode("utf-8") == (repo_root / independent.OUTPUT).read_bytes().decode("utf-8").replace(
        "\r\n", "\n"
    )


def test_the_independent_module_imports_nothing_from_the_readers():
    import ast
    import inspect

    tree = ast.parse(inspect.getsource(independent))
    imported = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported += [a.name for a in node.names]
        elif isinstance(node, ast.ImportFrom):
            imported.append(("." * node.level) + (node.module or ""))
    assert not [m for m in imported if m.startswith(".") or m.split(".")[0] == "ukfr"], imported


@pytest.mark.db
def test_the_loaded_data_agrees_with_the_independent_recomputation(db, repo_root):
    rows = committed(repo_root)
    assert len(rows) == 32
    loaded = {
        (r[0], r[1]): r
        for r in db.query(
            "SELECT f.release, f.filename, f.data_rows, f.primary_for_release, "
            "       fc.amount_sum_exact, fc.staged_amount_sum, fc.zero_rows, fc.staged_rows "
            "FROM raw.oscar_inyear_file AS f JOIN audit.file_control AS fc ON fc.file_id = f.file_id"
        )
    }
    assert set(loaded) == {(r["release"], r["filename"]) for r in rows}
    checked_primary = 0
    for r in rows:
        key = (r["release"], r["filename"])
        _, _, data_rows, primary, exact_sum, staged_sum, zero_rows, staged_rows = loaded[key]
        assert int(r["data_rows"]) == data_rows, f"{key}: row count"
        if primary != "Y":
            continue
        checked_primary += 1
        exact_tol = Decimal(0) if r["method"] == "csv" else EXACT_TOLERANCE
        rounded_tol = Decimal(0) if r["method"] == "csv" else ROUNDED_TOLERANCE
        assert abs(Decimal(exact_sum) - Decimal(r["amount_sum"])) <= exact_tol, f"{key}: exact sum"
        assert abs(staged_sum - Decimal(r["amount_sum_rounded_4dp"])) <= rounded_tol, f"{key}: rounded sum"
        if r["method"] == "csv":
            assert int(r["zero_rows"]) == zero_rows, f"{key}: zero rows"
            assert staged_rows == data_rows - zero_rows, f"{key}: staged rows"
    assert checked_primary == 31
