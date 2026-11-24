"""The workforce load against the built database and the files under UKFR_DATA_DIR (markers `db` and `localdata`)."""

from __future__ import annotations

import csv
import io
from decimal import Decimal
from pathlib import Path

import pytest

from ukfr.readers import workforce as w
from ukfr.stages.workforce import SKIPPED_CSV, read_skipped

pytestmark = [pytest.mark.db, pytest.mark.localdata]


def _loaded(db) -> bool:
    return bool(db.scalar("SELECT OBJECT_ID(N'raw.workforce_file')")) and bool(
        db.scalar("SELECT COUNT(*) FROM raw.workforce_file")
    )


def test_every_manifest_file_has_a_file_row_and_the_skipped_ones_are_the_listed_ones(db, repo_root):
    if not _loaded(db):
        pytest.skip("the workforce stage has not run in this database (build with --scope full)")
    files = w.list_workforce_files(repo_root)
    rows = db.query("SELECT release, filename, load_status FROM raw.workforce_file")
    assert len(rows) == len(files)
    assert {(r[0], r[1]) for r in rows} == {(f.release, f.filename) for f in files}
    skipped_in_db = {(r[0], r[1]) for r in rows if r[2] == "skipped"}
    listed = read_skipped(repo_root)
    assert skipped_in_db == set(listed)
    assert all(len(reason) > 20 for reason in listed.values()), f"every entry of {SKIPPED_CSV} needs a reason"


def _single_row_sum(path: Path, fmt: str) -> tuple[Decimal, int]:
    """Sum of the payroll total full-time equivalent of a one-row-header file, found by the header text alone and read
    with the spreadsheet library or the csv module directly (not through ukfr.readers)."""
    if fmt == "csv":
        text = path.read_bytes().decode("utf-8-sig", errors="replace")
        rows = list(csv.reader(io.StringIO(text, newline="")))
    else:
        from python_calamine import CalamineWorkbook

        wb = CalamineWorkbook.from_path(str(path))
        rows = None
        for name in wb.sheet_names:
            r = wb.get_sheet_by_name(name).to_python(skip_empty_area=False)
            if r and any("Organisation name" in str(c) for c in r[0]):
                rows = r
                break
        assert rows is not None
    header = [" ".join(str(c).lower().split()) for c in rows[0]]
    col = [
        i
        for i, h in enumerate(header)
        if h.startswith("payroll staff") and "total" in h and ("full-time" in h or "full time" in h)
    ]
    assert len(col) == 1, header
    total = Decimal(0)
    n = 0
    for r in rows[1:]:
        v = r[col[0]] if col[0] < len(r) else ""
        if v in ("", None):
            continue
        text = str(v).replace(",", "").replace("£", "").strip()
        total += Decimal(repr(float(text))) if isinstance(v, float) else Decimal(text)
        n += 1
    return total, n


@pytest.mark.parametrize(
    ("dept", "month", "fmt"),
    [("dft", "2026-10", "csv"), ("hmt", "2026-10", "xlsx"), ("nca", "2026-10", "ods")],
)
def test_the_payroll_fte_total_of_a_file_equals_an_independent_sum_read_by_header_text(db, repo_root, dept, month, fmt):
    if not _loaded(db):
        pytest.skip("the workforce stage has not run in this database (build with --scope full)")
    f = next(x for x in w.list_workforce_files(repo_root) if (x.dept, x.month, x.fmt) == (dept, month, fmt))
    expected, n = _single_row_sum(f.resolve(repo_root), fmt)
    got = db.query(
        "SELECT SUM(v.value), COUNT(*) FROM raw.workforce_value AS v "
        "JOIN raw.workforce_file AS f ON f.file_id = v.file_id "
        "WHERE f.release = ? AND f.filename = ? AND v.measure_key = 'payroll_total_fte'",
        (f.release, f.filename),
    )[0]
    assert got[1] == n
    assert abs(Decimal(got[0]) - expected) <= Decimal("0.0001") * n
