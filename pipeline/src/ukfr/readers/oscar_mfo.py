"""Read the departments' monthly forecast and outturn (MFO) returns.

Each zip (FY2021-22, FY2022-23) holds one comma-separated CSV per return, named like
`MFO-R07-2021-22.csv` (one member is `MFO-R09-202223.csv`). Every file has the same 91 columns as the
annual extracts, VERSION_CODE `Forecast` on every row, and all twelve months `P01` ... `P12`.
No column says whether a month is actual or forecast: that is derived from the return number.
"""

from __future__ import annotations

import csv
import io
import re
import zipfile
from collections.abc import Iterator
from contextlib import contextmanager
from decimal import Decimal
from pathlib import Path

from .oscar_extract import CONTROL_BUDGET_DETAIL, REQUIRED

ENCODING = "cp1252"
_MEMBER_RE = re.compile(r"MFO-R(\d{2})-(\d{4})-?(\d{2})\.csv$", re.IGNORECASE)
_PERIOD_RE = re.compile(r"^P(\d{2})$")

# In the MFO files CONTROL_BUDGET_L0_LONG_NAME holds the detail ("DEL PROG") and L1 the top level
# ("DEL"); in the annual extracts both are long names. Either way this gives the in-year spelling.
_DETAIL_SHORT = {"DEL PROG", "DEL ADMIN", "DEPT AME", "NON-DEPT AME", "NON-BUDGET"}


def control_budget_detail(l0: str, l1: str) -> str:
    for v in (l0, l1):
        if v in _DETAIL_SHORT:
            return v
        if v in CONTROL_BUDGET_DETAIL:
            return CONTROL_BUDGET_DETAIL[v]
    return l0 or l1


def parse_member(name: str) -> tuple[int, str]:
    """'MFO-R09-202223.csv' -> (9, '2022-23')."""
    m = _MEMBER_RE.search(name)
    if not m:
        raise ValueError(f"not an MFO return file name: {name!r}")
    return int(m.group(1)), f"{m.group(2)}-{m.group(3)}"


def returns(path: Path) -> list[tuple[int, str, str]]:
    """(return number, fiscal year, member name) for every return CSV in the zip, by return number."""
    with zipfile.ZipFile(path) as z:
        out = [(*parse_member(n), n) for n in z.namelist() if n.lower().endswith(".csv")]
    return sorted(out)


def parse_period(text: str) -> int:
    m = _PERIOD_RE.match(text.strip())
    if not m:
        raise ValueError(f"unrecognised MFO period {text!r}")
    return int(m.group(1))


def parse_amount(text: str) -> Decimal:
    s = text.strip()
    if not s:
        raise ValueError("empty AMOUNT")
    return Decimal(s)


def check_header(header: list[str]) -> dict[str, int]:
    missing = [c for c in REQUIRED if c not in header]
    if missing:
        raise ValueError(f"missing columns: {missing}")
    return {c: i for i, c in enumerate(header)}


class RepairStats:
    def __init__(self) -> None:
        self.joined: list[int] = []  # record numbers (header = 1) of rows rebuilt from two pieces


def repair_split_rows(rows: Iterator[list[str]], ncol: int, stats: RepairStats) -> Iterator[list[str]]:
    """Rejoin a record that was broken by a stray line break after its first field.

    `MFO-R05-2022-23.csv` has one such record: a line holding only `202223`, then a line starting
    with a comma that carries the other 90 fields. csv reads that as a 1-field row followed by a
    91-field row whose first field is empty. Any other short or long row is passed through unchanged
    so the caller can count and reject it."""
    n = 1
    pending: list[str] | None = None
    for row in rows:
        n += 1
        if pending is not None:
            if len(row) == ncol and row[0] == "":
                stats.joined.append(n - 1)
                yield [pending[0], *row[1:]]
                pending = None
                continue
            yield pending
            pending = None
        if len(row) == 1 and row[0] != "":
            pending = row
            continue
        yield row
    if pending is not None:
        yield pending


@contextmanager
def open_rows(stream: io.TextIOBase, stats: RepairStats | None = None):
    reader = csv.reader(stream, strict=True)
    header = next(reader)
    yield header, check_header(header), repair_split_rows(reader, len(header), stats or RepairStats())


@contextmanager
def open_return(path: Path, member: str, stats: RepairStats | None = None):
    """Yield (header, column index, row iterator) for one return CSV inside an MFO zip."""
    with zipfile.ZipFile(path) as z, z.open(member) as raw:
        text = io.TextIOWrapper(raw, encoding=ENCODING, errors="strict", newline="")
        with open_rows(text, stats) as opened:
            yield opened
