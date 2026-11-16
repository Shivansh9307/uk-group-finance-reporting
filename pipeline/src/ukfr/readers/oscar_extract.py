"""Read the OSCAR annual extracts (November 2022 release) as a stream.

Each zip holds one pipe-delimited, fully quoted txt with 91 columns, encoded Windows-1252 (the
2021-22 file has 0x92 apostrophes). Four of the five zips use Deflate64, so the member is
decompressed through `ukfr.zipstream.iter_member` and never written to disk.

AMOUNT is fixed-width text such as `" 000000000005000."` or `"-000000000000336."` (£000).
MONTH_SHORT_NAME is either a month (`Apr-17` ... `Mar-18`) or `Period 0 - 17-18`.
"""

from __future__ import annotations

import csv
import io
import re
from collections.abc import Iterator
from contextlib import contextmanager
from decimal import Decimal
from pathlib import Path

from .. import zipstream

ENCODING = "cp1252"
N_COLUMNS = 91

# The columns the profiling and the loaders rely on; the reader fails if any is missing.
REQUIRED = (
    "YEAR_SHORT_NAME",
    "MONTH_SHORT_NAME",
    "DEPARTMENT_GROUP_CODE",
    "DEPARTMENT_GROUP_LONG_NAME",
    "ORGANISATION_CODE",
    "SR_GROUP_LONG_NAME",
    "SEGMENT_L4_CODE",
    "CONTROL_BUDGET_L0_LONG_NAME",
    "CONTROL_BUDGET_L1_LONG_NAME",
    "ACCOUNTS_LONG_NAME",
    "CHART_OF_ACCOUNTS_L5_CODE",
    "ECONOMIC_BUDGET_CODE",
    "ECONOMIC_GROUP_CODE",
    "ECONOMIC_CATEGORY_CODE",
    "USAGE_CODE",
    "STATUS_CODE",
    "TYPE_CODE",
    "VERSION_CODE",
    "AMOUNT",
    "DATA_EFFECTIVE_DATETIME",
)

MONTHS = ("Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec", "Jan", "Feb", "Mar")
_PERIOD_RE = re.compile(r"^Period (\d{1,2}) - \d\d-\d\d$")
_MONTH_RE = re.compile(r"^([A-Z][a-z]{2})-\d\d$")

# Control budget detail as the in-year releases spell it, keyed by the extract's L1 name.
CONTROL_BUDGET_DETAIL = {
    "DEPARTMENTAL EXPENDITURE LIMITS PROGRAMME": "DEL PROG",
    "DEPARTMENTAL EXPENDITURE LIMITS ADMINISTRATION": "DEL ADMIN",
    "DEPARTMENTAL ANNUALLY MANAGED EXPENDITURE": "DEPT AME",
    "NON-DEPARTMENTAL ANNUALLY MANAGED EXPENDITURE": "NON-DEPT AME",
    "NON-BUDGET (NB)": "NON-BUDGET",
}


def parse_amount(text: str) -> Decimal:
    """`" 000000000005000."` -> Decimal('5000'); `"-000000000000336."` -> Decimal('-336')."""
    s = text.strip()
    if not s:
        raise ValueError("empty AMOUNT")
    return Decimal(s)


def month_period(month_short_name: str) -> int:
    """Fiscal period: `Period 0 - 17-18` -> 0, `Apr-17` -> 1, ..., `Mar-18` -> 12, `Period 13 - ..` -> 13."""
    m = _PERIOD_RE.match(month_short_name)
    if m:
        return int(m.group(1))
    m = _MONTH_RE.match(month_short_name)
    if m and m.group(1) in MONTHS:
        return MONTHS.index(m.group(1)) + 1
    raise ValueError(f"unrecognised MONTH_SHORT_NAME {month_short_name!r}")


def control_budget_detail(l1_long_name: str) -> str:
    return CONTROL_BUDGET_DETAIL.get(l1_long_name, l1_long_name)


class _Chunks(io.RawIOBase):
    """Raw stream over an iterator of byte chunks.

    Keeps an offset into the current chunk instead of re-slicing it: a highly compressed member
    inflates to chunks of 30 MB or more, and slicing one on every small read is quadratic.
    """

    def __init__(self, chunks: Iterator[bytes]):
        self._chunks = chunks
        self._buf = memoryview(b"")
        self._pos = 0

    def readable(self) -> bool:
        return True

    def close(self) -> None:
        close = getattr(self._chunks, "close", None)
        if close:
            close()
        super().close()

    def readinto(self, b) -> int:
        while self._pos >= len(self._buf):
            try:
                self._buf = memoryview(next(self._chunks))
            except StopIteration:
                return 0
            self._pos = 0
        n = min(len(b), len(self._buf) - self._pos)
        b[:n] = self._buf[self._pos : self._pos + n]
        self._pos += n
        return n


def text_stream(chunks: Iterator[bytes], encoding: str = ENCODING) -> io.TextIOWrapper:
    raw = io.BufferedReader(_Chunks(chunks), buffer_size=1 << 20)
    return io.TextIOWrapper(raw, encoding=encoding, errors="strict", newline="")


def member_name(path: Path) -> str:
    infos = [i for i in zipstream.members(path) if i.filename.lower().endswith(".txt")]
    if len(infos) != 1:
        raise ValueError(f"{path.name}: expected one .txt member, found {[i.filename for i in infos]}")
    return infos[0].filename


def check_header(header: list[str]) -> dict[str, int]:
    if len(header) != N_COLUMNS:
        raise ValueError(f"expected {N_COLUMNS} columns, found {len(header)}")
    missing = [c for c in REQUIRED if c not in header]
    if missing:
        raise ValueError(f"missing columns: {missing}")
    return {c: i for i, c in enumerate(header)}


@contextmanager
def open_rows(stream: io.TextIOBase):
    """(header, index, rows) over an open text stream of an extract."""
    reader = csv.reader(stream, delimiter="|", quotechar='"', strict=True)
    header = next(reader)
    yield header, check_header(header), reader


@contextmanager
def open_extract(path: Path, member: str | None = None):
    """Yield (header, column index, row iterator) for one extract zip, streaming the member."""
    name = member or member_name(path)
    with text_stream(zipstream.iter_member(path, name)) as t, open_rows(t) as opened:
        yield opened
