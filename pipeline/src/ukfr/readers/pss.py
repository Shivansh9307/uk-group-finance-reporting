"""Reader for the Public Spending Statistics database workbook (`PSS_Database_<year>.xlsx`).

The workbook has a `Metadata` sheet, a `Pivot Table` sheet and the `Database` sheet that this reader
loads: one header row of ten columns, then one row per year x SR group x segment x economic group x
control budget detail x ringfence, with the amount in thousands of pounds (spending positive).

Cells are read with `ukfr.readers.plans.read_workbook`, which takes numbers from the sheet XML as text
and returns exact `Decimal` values, so no amount passes through a float. Every cell is returned as
text; the amount is also returned as a `Decimal`. A header that is not the expected one raises
`PssFormatError`.
"""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path

from ..config import FILES_CSV, data_dir
from ..manifest import RAW_PREFIX, read_rows
from . import plans as rp

SOURCE_ID = "pss"
DATA_SHEET = "Database"

PSS_COLUMNS = (
    "Year",
    "Economic Budget Code",
    "Economic Ringfence Code",
    "Control Budget Code",
    "Control Budget Detail Code",
    "SR Group Long Name",
    "Segment Code",
    "Segment Long Name",
    "PESA Economic Group Long Name",
    "Amount",
)


class PssFormatError(ValueError):
    """The workbook is not in the layout this reader knows."""


@dataclass(frozen=True)
class PssFile:
    release: str  # e.g. '2026-07'
    filename: str
    path: str  # as in the manifest
    sha256: str

    @property
    def is_database(self) -> bool:
        return self.filename.lower().startswith("pss_database")

    def resolve(self, repo_root: Path) -> Path:
        if self.path.startswith(RAW_PREFIX):
            return data_dir(repo_root) / self.path[len(RAW_PREFIX) :]
        return repo_root / self.path


@dataclass(frozen=True, slots=True)
class PssRow:
    line: int  # 1-based row in the sheet (header = 1)
    values: tuple[str, ...]  # the ten columns as text, in PSS_COLUMNS order
    amount: Decimal | None


@dataclass
class PssStats:
    total_rows: int = 0
    blank_rows: int = 0
    data_rows: int = 0
    sheets: list[str] = field(default_factory=list)


def list_pss_files(repo_root: Path) -> list[PssFile]:
    """Every fetched PSS file in the manifest, database or not (the loader records the others as skipped)."""
    out = [
        PssFile(r.release, r.filename, r.path, r.sha256)
        for r in read_rows(repo_root / FILES_CSV)
        if r.source_id == SOURCE_ID and r.fetched == "yes" and r.filename.lower().endswith(".xlsx")
    ]
    return sorted(out, key=lambda f: (f.release, f.filename))


def _text(v) -> str:
    if v is None:
        return ""
    if isinstance(v, Decimal):
        s = format(v, "f")
        if "." in s:
            s = s.rstrip("0").rstrip(".")
        return "0" if s in ("", "-0") else s
    return str(v).strip()


def read_pss(f: PssFile, repo_root: Path, stats: PssStats | None = None) -> Iterator[PssRow]:
    stats = stats if stats is not None else PssStats()
    where = f.filename
    path = f.resolve(repo_root)
    stats.sheets = rp.sheet_names(path)
    if DATA_SHEET not in stats.sheets:
        raise PssFormatError(f"{where}: no sheet named {DATA_SHEET!r}")
    rows = rp.read_workbook(path, only={DATA_SHEET})[DATA_SHEET]
    header = tuple(_text(c) for c in rows[0]) if rows else ()
    while header and not header[-1]:
        header = header[:-1]
    if header != PSS_COLUMNS:
        raise PssFormatError(f"{where}: header is not the PSS layout: {list(header)}")
    width = len(PSS_COLUMNS)
    for i, raw in enumerate(rows[1:], start=2):
        stats.total_rows += 1
        if len(raw) > width and any(_text(c) for c in raw[width:]):
            raise PssFormatError(f"{where} row {i}: data beyond column {width}")
        cells = list(raw[:width]) + [None] * (width - len(raw))
        texts = tuple(_text(c) for c in cells)
        if not any(texts):
            stats.blank_rows += 1
            continue
        amount_cell = cells[-1]
        if amount_cell is None or (isinstance(amount_cell, str) and not amount_cell.strip()):
            amount = None
        elif isinstance(amount_cell, Decimal):
            amount = amount_cell
        else:
            raise PssFormatError(f"{where} row {i}: amount {amount_cell!r} is not a number")
        stats.data_rows += 1
        yield PssRow(i, texts, amount)
