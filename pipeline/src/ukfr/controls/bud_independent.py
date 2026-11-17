"""Recompute the BUD workbooks' and the PSS database's row counts and amount sums without `ukfr.readers`.

`data/audit/bud_file_control_totals.csv` and `pss_file_control_totals.csv` were produced by the same
readers the loader uses, so on their own they cannot catch a reader fault. This module is the second
opinion. It opens each sheet directly with `python-calamine`, finds the columns by their header text
(`AMOUNT`, `STATUS_CODE`, `YEAR_NO` for BUD; `Amount`, `Year` for PSS), and sums with `Decimal`. It
lists the files by scanning the data folder and imports nothing else from this package.

What it counts: a data row is a row after the header with at least one non-blank cell. A cell that is
a float is turned into a `Decimal` through its shortest round-trip text, and must be a whole number
or the run stops, because a fractional amount would make the float sum unreliable.

Outputs, sorted, LF line ends, no paths and no timestamps:
- `data/audit/bud_independent_control.csv`: one row per workbook
- `data/audit/pss_independent_control.csv`: one row per financial year of the PSS database
"""

from __future__ import annotations

import csv
import hashlib
import os
from decimal import Decimal
from pathlib import Path

BUD_OUTPUT = Path("data") / "audit" / "bud_independent_control.csv"
PSS_OUTPUT = Path("data") / "audit" / "pss_independent_control.csv"
BUD_COLUMNS = (
    "vintage",
    "filename",
    "sha256",
    "financial_year",
    "total_rows",
    "blank_rows",
    "data_rows",
    "closed_rows",
    "amount_sum_all_rows",
    "amount_sum_excluding_closed",
    "amount_closed",
)
PSS_COLUMNS = ("filename", "sheet", "financial_year", "data_rows", "amount_sum")


def _data_root(repo_root: Path) -> Path:
    env = os.environ.get("UKFR_DATA_DIR")
    return Path(env) if env else repo_root / "data" / "raw"


def _plain(d: Decimal) -> str:
    s = format(d, "f")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s


def _text(v) -> str:
    if v is None:
        return ""
    if isinstance(v, float):
        return str(int(v)) if v.is_integer() else repr(v)
    return str(v).strip()


def _amount(v, where: str) -> Decimal:
    if v is None or (isinstance(v, str) and not v.strip()):
        raise SystemExit(f"{where}: blank amount")
    if isinstance(v, bool):
        raise SystemExit(f"{where}: boolean amount")
    if isinstance(v, int):
        return Decimal(v)
    if isinstance(v, float):
        if not v.is_integer():
            raise SystemExit(f"{where}: fractional amount {v!r}")
        return Decimal(int(v))
    return Decimal(str(v).replace(",", "").strip())


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def _sheet_with_header(wb, must_have: str):
    """(sheet name, rows) of the sheet whose first row holds a cell headed `must_have`."""
    for name in wb.sheet_names:
        rows = wb.get_sheet_by_name(name).to_python(skip_empty_area=False)
        if rows and must_have in [_text(c) for c in rows[0]]:
            return name, rows
    raise SystemExit(f"no sheet has a column headed {must_have!r}")


def bud_rows(repo_root: Path) -> list[list[str]]:
    from python_calamine import CalamineWorkbook

    base = _data_root(repo_root) / "oscar_annual_bud"
    out: list[list[str]] = []
    for path in sorted(base.glob("*/BUD*.xlsx")):
        vintage = path.parent.name
        wb = CalamineWorkbook.from_path(str(path))
        _name, rows = _sheet_with_header(wb, "AMOUNT")
        header = [_text(c) for c in rows[0]]
        i_amount, i_status, i_year = header.index("AMOUNT"), header.index("STATUS_CODE"), header.index("YEAR_NO")
        total = blank = data = closed_rows = 0
        everything = excluding = closed = Decimal(0)
        years: set[str] = set()
        for n, row in enumerate(rows[1:], start=2):
            total += 1
            if not any(_text(c) for c in row):
                blank += 1
                continue
            data += 1
            a = _amount(row[i_amount], f"{path.name} row {n}")
            everything += a
            years.add(_text(row[i_year]))
            if _text(row[i_status]) == "Closed":
                closed_rows += 1
                closed += a
            else:
                excluding += a
        if len(years) != 1:
            raise SystemExit(f"{path.name}: expected one YEAR_NO, found {sorted(years)}")
        year = next(iter(years))
        out.append(
            [
                vintage,
                path.name,
                _sha256(path),
                f"{year[:4]}-{year[4:]}",
                str(total),
                str(blank),
                str(data),
                str(closed_rows),
                _plain(everything),
                _plain(excluding),
                _plain(closed),
            ]
        )
    return sorted(out, key=lambda r: (r[0], r[1]))


def pss_rows(repo_root: Path) -> list[list[str]]:
    from python_calamine import CalamineWorkbook

    base = _data_root(repo_root) / "pss"
    out: list[list[str]] = []
    for path in sorted(base.glob("*/PSS_Database*.xlsx")):
        wb = CalamineWorkbook.from_path(str(path))
        sheet, rows = _sheet_with_header(wb, "Amount")
        header = [_text(c) for c in rows[0]]
        i_amount, i_year = header.index("Amount"), header.index("Year")
        count: dict[str, int] = {}
        total: dict[str, Decimal] = {}
        for n, row in enumerate(rows[1:], start=2):
            if not any(_text(c) for c in row):
                continue
            y = _text(row[i_year])
            count[y] = count.get(y, 0) + 1
            total[y] = total.get(y, Decimal(0)) + _amount(row[i_amount], f"{path.name} row {n}")
        for y in sorted(count):
            out.append([path.name, sheet, y, str(count[y]), _plain(total[y])])
    return sorted(out, key=lambda r: (r[0], r[2]))


def _write(path: Path, header: tuple[str, ...], rows: list[list[str]]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)
    return path


def run_bud(repo_root: Path, out: Path | None = None) -> Path:
    rows = bud_rows(repo_root)
    if not rows:
        raise SystemExit("no BUD workbooks found under the data folder (set UKFR_DATA_DIR)")
    return _write(out or repo_root / BUD_OUTPUT, BUD_COLUMNS, rows)


def run_pss(repo_root: Path, out: Path | None = None) -> Path:
    rows = pss_rows(repo_root)
    if not rows:
        raise SystemExit("no PSS database found under the data folder (set UKFR_DATA_DIR)")
    return _write(out or repo_root / PSS_OUTPUT, PSS_COLUMNS, rows)
