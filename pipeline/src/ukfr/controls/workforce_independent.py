"""Recompute the workforce files' row counts and column sums without `ukfr.readers`.

The loader reads each file through `ukfr.readers.workforce`, which decides what the header means. This module is the
second opinion on the numbers. It does not interpret any header. It opens every fetched file by itself (`csv` for
csv, `python-calamine` for xlsx, xls and ods). The identifier columns end at the last header cell that is
"Organisation type" or starts with "Main" ("Main, parent or sponsoring department"). Data rows are the non-blank
rows from the first one that holds a number after the identifier columns. For every later column it adds up
the cells that are numbers, with `Decimal`. A number is a float
cell, or a text cell once pound signs, thousands commas and spaces are removed. A non-blank cell that is neither is
counted as non-numeric.

The loader stores the column position of every value, so SQL can compare, for each file and column, the count and the
exact sum that the loader holds with the numbers here. A header read wrongly shows up elsewhere (the header tests); a
number read wrongly or dropped shows up here.

It lists the files by scanning the data folder and imports nothing else from this package. The file list is the
folders under `<data dir>/workforce_mi/<dept>-<yyyy>-<mm>/`.

The stage loads the rows into `raw.workforce_control_expected`, one per file and column: dept, month, filename,
sheet, column_index (0-based), data_rows (non-blank rows after the header), numeric_cells, nonnumeric_cells and
value_sum. `run` can also write them to a CSV (sorted, LF line ends, no paths, no timestamps).
"""

from __future__ import annotations

import csv
import io
import os
import re
from decimal import ROUND_HALF_UP, Context, Decimal
from pathlib import Path

OUTPUT = Path("data") / "audit" / "workforce_independent_control.csv"
COLUMNS = (
    "dept",
    "month",
    "filename",
    "sheet",
    "column_index",
    "data_rows",
    "numeric_cells",
    "nonnumeric_cells",
    "value_sum",
)
_NUM = re.compile(r"\d+(?:\.\d+)?|\.\d+")
_FIFTEEN = Context(prec=15)
SUFFIXES = (".csv", ".xlsx", ".xls", ".ods")


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


def _four(d: Decimal) -> Decimal:
    """4 decimal places: spreadsheets keep 16 or 17 digits of float noise (and residues such as 2.27e-13 where a sum
    should be 0), and nothing finer than 1e-4 of a person or a pound is meant."""
    return d.quantize(Decimal("1e-4"), rounding=ROUND_HALF_UP)


def _number(v) -> Decimal | None:
    """The cell as a number, or None when it is not one (blank cells are handled by the caller)."""
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return _four(_FIFTEEN.create_decimal(repr(v))) if isinstance(v, float) else Decimal(v)
    s = str(v).replace("\xa0", " ").strip()
    neg = False
    if s.startswith("(") and s.endswith(")"):
        neg, s = True, s[1:-1].strip()
    while s.startswith("-"):
        neg, s = True, s[1:].strip()
    s = "".join(ch for ch in s if ch not in "£Â�").replace(",", "").strip()
    while s.startswith("-"):
        neg, s = True, s[1:].strip()
    if not _NUM.fullmatch(s):
        return None
    d = _four(_FIFTEEN.create_decimal(s))
    return -d if neg else d


def _sheets(path: Path) -> dict[str, list[list]]:
    if path.suffix.lower() == ".csv":
        raw = path.read_bytes()
        try:
            text = raw.decode("utf-8-sig")
        except UnicodeDecodeError:
            text = raw.decode("cp1252")
        return {"csv": list(csv.reader(io.StringIO(text, newline="")))}
    from python_calamine import CalamineWorkbook

    wb = CalamineWorkbook.from_path(str(path))
    return {n: wb.get_sheet_by_name(n).to_python(skip_empty_area=False) for n in wb.sheet_names}


def file_rows(path: Path) -> tuple[str, int, list[list]] | None:
    """(sheet, first measure column, data rows) of the one sheet that is a data sheet, or None for a file in a
    layout this control does not know.

    A data sheet has, near its top, a header row with 'Organisation type' or a cell starting 'Main' (the identifier
    columns end at the last of them), or, for the files that had their header rows removed, a row with 'AO/AA' (the
    identifier columns are the first three); the header rows say 'headcount' or 'equivalent' somewhere; and a number
    follows.
    Data rows are the non-blank rows from the first row that holds a number after the identifier columns."""
    found = []
    for name, rows in _sheets(path).items():
        top = rows[:15]
        ident = [
            i
            for r in top
            for i, c in enumerate(r)
            if " ".join(_text(c).lower().split()) == "organisation type" or _text(c).lower().startswith("main")
        ]
        if ident:
            first = max(ident) + 1
        elif any(" ".join(_text(c).lower().split()) == "ao/aa" for r in top for c in r):
            first = 3
        else:
            continue
        start = next(
            (i for i, r in enumerate(rows[:60]) if any(_text(c) != "" and _number(c) is not None for c in r[first:])),
            None,
        )
        if start is None or start > 12:
            continue
        header_text = " ".join(_text(c).lower() for r in rows[:start] for c in r)
        if "headcount" not in header_text and "equivalent" not in header_text:
            continue
        found.append((name, first, [r for r in rows[start:] if any(_text(c) != "" for c in r)]))
    return found[0] if len(found) == 1 else None  # two candidate sheets is a layout I do not recompute either


def control_rows(repo_root: Path) -> list[list[str]]:
    base = _data_root(repo_root) / "workforce_mi"
    out: list[list[str]] = []
    for path in sorted(p for p in base.glob("*/*") if p.suffix.lower() in SUFFIXES):
        m = re.fullmatch(r"([a-z0-9]+)-(\d{4})-(\d{2})", path.parent.name)
        if not m:
            raise SystemExit(f"{path}: the folder is not <dept>-<yyyy>-<mm>")
        dept, month = m.group(1), f"{m.group(2)}-{m.group(3)}"
        found = file_rows(path)
        if found is None:
            continue  # a layout I do not recompute; the files the reader cannot read are listed in the skip list
        sheet, first, data = found
        width = max(len(r) for r in data)
        for col in range(first, width):
            n = bad = 0
            total = Decimal(0)
            for r in data:
                v = r[col] if col < len(r) else None
                if _text(v) == "":
                    continue
                d = _number(v)
                if d is None:
                    bad += 1
                else:
                    n += 1
                    total += d
            if n or bad:
                out.append([dept, month, path.name, sheet, str(col), str(len(data)), str(n), str(bad), _plain(total)])
    return sorted(out, key=lambda r: (r[0], r[1], r[2], int(r[4])))


def run(repo_root: Path, out: Path | None = None) -> Path:
    rows = control_rows(repo_root)
    if not rows:
        raise SystemExit("no workforce files found under the data folder (set UKFR_DATA_DIR)")
    path = out or repo_root / OUTPUT
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(COLUMNS)
        w.writerows(rows)
    return path
