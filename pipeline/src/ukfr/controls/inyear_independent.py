"""Recompute each in-year file's row count and amount sum without `ukfr.readers`.

The control table `data/audit/inyear_file_control_totals.csv` was made by the same reader the loader
uses, so on its own it cannot catch a reader fault. This module is the second opinion: a plain `csv`
pass over each zip member (Windows-1252), and `python-calamine` for ODS sheets. It reads the file
list from `data/manifest/files.csv` with the `csv` module and imports nothing else from this package.

What it counts: a data row is a row after the header with at least one non-blank cell. The amount is
the cell of the column headed `Amount`, read with `Decimal` after removing thousands separators.

Exactness: CSV amounts are exact. Calamine hands ODS numbers over as binary floats, so for ODS files
each amount is the shortest decimal that round-trips the float; the sum can differ from the exact
text sum by the float residue (the caller states the tolerance it applies).

Output: `data/audit/inyear_independent_control.csv`, sorted by release and file name.
"""

from __future__ import annotations

import csv
import io
import zipfile
from decimal import ROUND_HALF_UP, Decimal, localcontext
from pathlib import Path

OUTPUT = Path("data") / "audit" / "inyear_independent_control.csv"
COLUMNS = ["release", "filename", "method", "data_rows", "zero_rows", "amount_sum", "amount_sum_rounded_4dp"]
_PREC = 80


def _plain(d: Decimal) -> str:
    s = format(d, "f")  # exact; normalize() would round to the context precision
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s


def _manifest_files(repo_root: Path) -> list[tuple[str, str, Path, str]]:
    """(release, filename, path, member) for each fetched in-year data file in the manifest."""
    out = []
    with open(repo_root / "data" / "manifest" / "files.csv", encoding="utf-8", newline="") as fh:
        for r in csv.DictReader(fh):
            name = r["filename"].lower()
            if r["source_id"] != "oscar_inyear" or r["fetched"] != "yes":
                continue
            if not name.endswith((".zip", ".csv", ".ods")):
                continue
            if r["path"].startswith("$"):
                raise SystemExit(f"{r['filename']} is not a committed file: {r['path']}")
            member = ""
            if name.endswith(".zip"):
                with zipfile.ZipFile(repo_root / r["path"]) as zf:
                    inner = [n for n in zf.namelist() if n.lower().endswith((".csv", ".ods"))]
                if len(inner) != 1:
                    raise SystemExit(f"{r['filename']}: expected one csv or ods member, found {inner}")
                member = inner[0]
            out.append((r["release"], r["filename"], repo_root / r["path"], member))
    return sorted(out, key=lambda t: (t[0], t[1]))


def _bytes(path: Path, member: str) -> bytes:
    if member:
        with zipfile.ZipFile(path) as zf:
            return zf.read(member)
    return path.read_bytes()


def _csv_amounts(data: bytes):
    reader = csv.reader(io.StringIO(data.decode("cp1252"), newline=""))
    header = [c.strip().lower() for c in next(reader)]
    col = header.index("amount")
    for row in reader:
        if not any(c.strip() for c in row):
            continue
        yield (row[col] if col < len(row) else "").strip()


def _ods_amounts(data: bytes):
    from python_calamine import CalamineWorkbook

    book = CalamineWorkbook.from_filelike(io.BytesIO(data))
    for name in book.sheet_names:
        rows = book.get_sheet_by_name(name).iter_rows()
        header = next(rows, None)
        if header is None:
            continue
        labels = [str(c).strip().lower() for c in header]
        if "amount" not in labels or "organisation code" not in labels:
            continue
        col = labels.index("amount")
        for row in rows:
            if not any(str(c).strip() for c in row):
                continue
            yield row[col] if col < len(row) else ""
        return
    raise SystemExit("no sheet with Organisation Code and Amount headers")


def _to_decimal(value) -> Decimal | None:
    if value is None:
        return None
    if isinstance(value, bool):
        raise ValueError(f"boolean amount {value!r}")
    if isinstance(value, int):
        return Decimal(value)
    if isinstance(value, float):
        return Decimal(repr(value))
    text = str(value).strip().replace(",", "")
    return Decimal(text) if text else None


def recompute(repo_root: Path) -> list[dict[str, str]]:
    rows = []
    for release, filename, path, member in _manifest_files(repo_root):
        data = _bytes(path, member)
        is_ods = (member or filename).lower().endswith(".ods")
        cells = _ods_amounts(data) if is_ods else _csv_amounts(data)
        n = zeros = 0
        total = Decimal(0)
        total4 = Decimal(0)
        with localcontext() as ctx:
            ctx.prec = _PREC
            for cell in cells:
                n += 1
                amount = _to_decimal(cell)
                if amount is None:
                    continue
                if amount == 0:
                    zeros += 1
                total += amount
                total4 += amount.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)
        rows.append(
            {
                "release": release,
                "filename": filename,
                "method": "ods-calamine" if is_ods else "csv",
                "data_rows": str(n),
                "zero_rows": str(zeros),
                "amount_sum": _plain(total),
                "amount_sum_rounded_4dp": _plain(total4),
            }
        )
    return rows


def write(rows: list[dict[str, str]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=COLUMNS, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)


def run(repo_root: Path, out: Path | None = None) -> Path:
    path = out or repo_root / OUTPUT
    write(recompute(repo_root), path)
    return path
