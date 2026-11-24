"""Recompute the row count and amount sum of every forecast return, month by month, without `ukfr.readers`.

The loader (`ukfr.stages.forecast_returns`) reads the annual extracts and the MFO zips through the shared
readers and adds the rows up into cells. This module is the second opinion: it opens the zips itself
(`zipfile` for the MFO csv files, `inflate64` for the Deflate64 extract members), reads them with the
`csv` module, finds the columns by their header text (`VERSION_CODE`, `MONTH_SHORT_NAME`, `AMOUNT`,
`YEAR_SHORT_NAME`), turns the month text into a period number with its own table, and adds the amounts
with `Decimal`. It lists the files by scanning the data folder and imports nothing else from this package.

What it counts: a data row is a record after the header that has as many fields as the header. (One MFO
record is broken by a stray line break: the 1-field fragment is not a data row, and the 91-field record
that follows it, whose first field is empty, is.) A return of an annual extract is the rows whose
`VERSION_CODE` is `R<n>`; the plans are not counted. A return of an MFO zip is one csv member.

Output, sorted, LF line ends, no paths and no timestamps: `data/audit/forecast_independent_control.csv`,
one row per family x financial year x return x period (period 0 included), with the data rows and the
exact amount sum in GBP thousands.
"""

from __future__ import annotations

import csv
import io
import os
import re
import struct
import zipfile
import zlib
from decimal import Decimal
from pathlib import Path

import inflate64

OUTPUT = Path("data") / "audit" / "forecast_independent_control.csv"
COLUMNS = ["family", "financial_year", "return_no", "period", "data_rows", "amount_sum"]
EXTRACT_YEARS = ("2017_18", "2018_19", "2019_20", "2020_21")
_MONTHS = {
    m: i for i, m in enumerate(("Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec", "Jan", "Feb", "Mar"), 1)
}


def _data_root() -> Path:
    env = os.environ.get("UKFR_DATA_DIR")
    if not env:
        raise SystemExit("set UKFR_DATA_DIR to the folder that holds the fetched source files")
    return Path(env)


def _plain(d: Decimal) -> str:
    s = format(d, "f")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s


def _period(text: str) -> int:
    t = text.strip()
    m = re.fullmatch(r"Period (\d+) - \d\d-\d\d", t)
    if m:
        return int(m.group(1))
    m = re.fullmatch(r"([A-Z][a-z]{2})-\d\d", t)
    if m and m.group(1) in _MONTHS:
        return _MONTHS[m.group(1)]
    m = re.fullmatch(r"P(\d\d)", t)
    if m:
        return int(m.group(1))
    raise SystemExit(f"unrecognised month text {text!r}")


class _Stream(io.RawIOBase):
    """Decompressed bytes of one zip member, read from the file on demand (method 0, 8 or 9)."""

    def __init__(self, zip_path: Path, name: str):
        with zipfile.ZipFile(zip_path) as z:
            info = z.getinfo(name)
        self._fh = open(zip_path, "rb")
        self._fh.seek(info.header_offset)
        head = self._fh.read(30)
        name_len, extra_len = struct.unpack("<HH", head[26:30])
        self._fh.seek(info.header_offset + 30 + name_len + extra_len)
        self._left = info.compress_size
        self._method = info.compress_type
        if self._method == 8:
            self._inflate = zlib.decompressobj(-15).decompress
        elif self._method == 9:
            self._inflate = inflate64.Inflater().inflate
        elif self._method == 0:
            self._inflate = bytes
        else:
            raise SystemExit(f"{name}: zip method {self._method} is not handled")
        self._buf = memoryview(b"")
        self._pos = 0

    def readable(self) -> bool:
        return True

    def close(self) -> None:
        self._fh.close()
        super().close()

    def readinto(self, b) -> int:
        while self._pos >= len(self._buf):
            if self._left <= 0:
                return 0
            raw = self._fh.read(min(1 << 20, self._left))
            if not raw:
                raise SystemExit("truncated zip member")
            self._left -= len(raw)
            self._buf = memoryview(self._inflate(raw))
            self._pos = 0
        n = min(len(b), len(self._buf) - self._pos)
        b[:n] = self._buf[self._pos : self._pos + n]
        self._pos += n
        return n


def _records(zip_path: Path, name: str, delimiter: str):
    raw = io.BufferedReader(_Stream(zip_path, name), buffer_size=1 << 20)
    with io.TextIOWrapper(raw, encoding="cp1252", errors="strict", newline="") as text:
        yield from csv.reader(text, delimiter=delimiter, quotechar='"')


def _add(totals: dict, key: tuple, amount: Decimal) -> None:
    t = totals.get(key)
    if t is None:
        totals[key] = [1, amount]
    else:
        t[0] += 1
        t[1] += amount


def _extract(zip_path: Path, family: str) -> dict:
    totals: dict = {}
    names = [n for n in zipfile.ZipFile(zip_path).namelist() if n.lower().endswith(".txt")]
    if len(names) != 1:
        raise SystemExit(f"{zip_path.name}: expected one txt member, found {names}")
    it = _records(zip_path, names[0], "|")
    header = next(it)
    i_ver, i_month, i_amt, i_year = (
        header.index(c) for c in ("VERSION_CODE", "MONTH_SHORT_NAME", "AMOUNT", "YEAR_SHORT_NAME")
    )
    width = len(header)
    for row in it:
        if len(row) != width:
            continue
        ver = row[i_ver]
        if not re.fullmatch(r"R\d+", ver):
            continue
        _add(totals, (family, row[i_year], int(ver[1:]), _period(row[i_month])), Decimal(row[i_amt].strip()))
    return totals


def _mfo(zip_path: Path, family: str) -> dict:
    totals: dict = {}
    for name in sorted(n for n in zipfile.ZipFile(zip_path).namelist() if n.lower().endswith(".csv")):
        m = re.search(r"MFO-R(\d+)-(\d{4})-?(\d{2})\.csv$", name, re.IGNORECASE)
        if not m:
            raise SystemExit(f"unexpected member name {name}")
        year = f"{m.group(2)}-{m.group(3)}"
        it = _records(zip_path, name, ",")
        header = next(it)
        i_month, i_amt = header.index("MONTH_SHORT_NAME"), header.index("AMOUNT")
        width = len(header)
        for row in it:
            if len(row) != width:
                continue
            _add(totals, (family, year, int(m.group(1)), _period(row[i_month])), Decimal(row[i_amt].strip()))
    return totals


def run(repo_root: Path, out: Path | None = None) -> Path:
    root = _data_root()
    totals: dict = {}
    for year in EXTRACT_YEARS:
        found = sorted((root / "oscar_annual_extract").glob(f"*/2022_OSCAR_Extract_{year}.zip"))
        if len(found) != 1:
            raise SystemExit(f"expected one extract zip for {year}, found {found}")
        totals.update(_extract(found[0], "extract"))
    mfo = sorted((root / "oscar_mfo").glob("*/*.zip"))
    if len(mfo) != 2:
        raise SystemExit(f"expected two MFO zips, found {[p.name for p in mfo]}")
    for p in mfo:
        totals.update(_mfo(p, "mfo"))
    path = out or repo_root / OUTPUT
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(COLUMNS)
        for key in sorted(totals):
            n, amount = totals[key]
            w.writerow([*key, n, _plain(amount)])
    return path
