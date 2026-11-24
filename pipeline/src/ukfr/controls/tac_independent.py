"""Recompute the TAC data workbooks' row counts and value sums without `ukfr.readers`.

The loader reads the sheet XML itself. This module is the second opinion: it opens each `All data`
sheet with `python-calamine`, finds the worksheet-name and value columns by their header text, and
adds up the values with `Decimal`, per worksheet. It scans the data folder for the files and imports
nothing else from this package.

What it counts: a data row is a row after the header with at least one non-blank cell. A value that
comes back as a float is turned into a `Decimal` through its shortest round-trip text, so a stored
`-9673.77933` is that number exactly; values carry at most five decimal places and at most 15
significant digits, so the float holds them without loss (the run stops on a value with more than 15
significant digits rather than guess).

Output `data/audit/tac_independent_control.csv`, sorted, LF line ends, no paths and no timestamps:
one row per data workbook and worksheet, with the rows and the exact sum of the value column. Every
worksheet is counted, not only the three statements the loader keeps.
"""

from __future__ import annotations

import csv
import os
import re
from decimal import Decimal
from pathlib import Path

OUTPUT = Path("data") / "audit" / "tac_independent_control.csv"
COLUMNS = ("release", "filename", "worksheet", "data_rows", "value_sum")
VALUE_HEADERS = {"total", "valuenumber"}
SHEET_HEADER = "worksheetname"


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


def _key(v) -> str:
    return re.sub(r"\s+", "", _text(v)).lower()


def _value(v, where: str) -> Decimal:
    if v is None or (isinstance(v, str) and not v.strip()):
        raise SystemExit(f"{where}: blank value")
    if isinstance(v, bool):
        raise SystemExit(f"{where}: boolean value")
    if isinstance(v, int):
        return Decimal(v)
    if isinstance(v, float):
        d = Decimal(repr(v))
        if len(d.as_tuple().digits) > 15:
            raise SystemExit(f"{where}: {v!r} has more than 15 significant digits")
        return d
    return Decimal(str(v).replace(",", "").strip())


def tac_rows(repo_root: Path) -> list[list[str]]:
    from python_calamine import CalamineWorkbook

    base = _data_root(repo_root) / "tac"
    out: list[list[str]] = []
    for path in sorted(base.glob("*/TAC-data-published*.xlsx")):
        release = path.parent.name
        wb = CalamineWorkbook.from_path(str(path))
        sheet = [n for n in wb.sheet_names if " ".join(n.split()).lower() == "all data"]
        if len(sheet) != 1:
            raise SystemExit(f"{path.name}: expected one 'All data' sheet, found {sheet}")
        rows = wb.get_sheet_by_name(sheet[0]).to_python(skip_empty_area=False)
        header = [_key(c) for c in rows[0]]
        i_ws = header.index(SHEET_HEADER)
        i_val = [i for i, h in enumerate(header) if h in VALUE_HEADERS]
        if len(i_val) != 1:
            raise SystemExit(f"{path.name}: expected one value column, header is {header}")
        i_val = i_val[0]
        count: dict[str, int] = {}
        total: dict[str, Decimal] = {}
        for n, row in enumerate(rows[1:], start=2):
            if not any(_text(c) for c in row):
                continue
            ws = " ".join(_text(row[i_ws]).split())
            count[ws] = count.get(ws, 0) + 1
            total[ws] = total.get(ws, Decimal(0)) + _value(row[i_val], f"{path.name} row {n}")
        for ws in sorted(count):
            out.append([release, path.name, ws, str(count[ws]), _plain(total[ws])])
    return sorted(out, key=lambda r: (r[0], r[1], r[2]))


def run(repo_root: Path, out: Path | None = None) -> Path:
    rows = tac_rows(repo_root)
    if not rows:
        raise SystemExit("no TAC data workbooks found under the data folder (set UKFR_DATA_DIR)")
    path = out or repo_root / OUTPUT
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(COLUMNS)
        w.writerows(rows)
    return path
