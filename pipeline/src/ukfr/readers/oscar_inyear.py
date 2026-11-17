"""Reader for the OSCAR II in-year releases (one quarterly snapshot per file).

`read_inyear(f)` yields one `InyearRow` per data line of any release, whatever its packaging (zip
holding a CSV, bare CSV, zip holding an ODS, bare ODS) and whichever of the four header layouts it
uses. It never guesses: an unknown header, an undecodable byte or an amount it cannot read
exactly raises `InyearFormatError` naming the file and line.

What it does, and nothing more:
- maps the source header to canonical column names (`HEADER_VARIANTS`);
- decodes CSV text as Windows-1252, the encoding every release uses (see the profiling notes);
- parses Amount into an exact `Decimal` and records which textual form it had;
- drops fully blank rows and counts them;
- derives the financial year and period (April = 1) from Month, keeping Year/Quarter/Month raw;
- attaches the release label from `data/manifest/files.csv`.
"""

from __future__ import annotations

import csv
import io
import re
import zipfile
from collections import Counter
from collections.abc import Iterator
from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import NamedTuple

from ..config import FILES_CSV, data_dir
from ..manifest import RAW_PREFIX, read_rows
from . import ods

SOURCE_ID = "oscar_inyear"
ENCODING = "cp1252"

# Canonical column names, in output order. `pesa_economic_group_name` exists only in the 2019 layout.
CANONICAL = (
    "organisation_code",
    "organisation_name",
    "control_budget_code",
    "control_budget_detail_code",
    "department_name",
    "sub_segment_code",
    "sub_segment_name",
    "economic_category_code",
    "economic_category_name",
    "economic_budget_code",
    "pesa_economic_group_code",
    "pesa_economic_group_name",
    "version",
    "year",
    "quarter",
    "month",
    "amount",
)

# variant name -> source header, column by column, mapped to canonical names.
# The name is the first release that used the layout.
HEADER_VARIANTS: dict[str, tuple[tuple[str, str], ...]] = {
    "v2019": (
        ("Organisation Code", "organisation_code"),
        ("Organisation", "organisation_name"),
        ("Control Budget Code", "control_budget_code"),
        ("Control Budget Detail Code", "control_budget_detail_code"),
        ("Segment Department Long Name", "department_name"),
        ("Sub Segment Code", "sub_segment_code"),
        ("Sub Segment Long Name", "sub_segment_name"),
        ("Economic Category Code", "economic_category_code"),
        ("Economic Category Long Name", "economic_category_name"),
        ("Economic Budget Code", "economic_budget_code"),
        ("PESA Economic Group Code", "pesa_economic_group_code"),
        ("PESA Economic Group Long Name", "pesa_economic_group_name"),
        ("Version", "version"),
        ("Year", "year"),
        ("Quarter", "quarter"),
        ("Month", "month"),
        ("Amount", "amount"),
    ),
    "v2021sep": (
        ("Organisation Code", "organisation_code"),
        ("Organisation Name", "organisation_name"),
        ("Control Budget Code", "control_budget_code"),
        ("Control Budget Detail", "control_budget_detail_code"),
        ("Department", "department_name"),
        ("Sub-segment Code", "sub_segment_code"),
        ("Sub-segment Name", "sub_segment_name"),
        ("Economic Category Code", "economic_category_code"),
        ("Economic Category Name", "economic_category_name"),
        ("Economic Budget", "economic_budget_code"),
        ("PESA Economic Group Code", "pesa_economic_group_code"),
        ("Version Snapshot", "version"),
        ("Year", "year"),
        ("Quarter", "quarter"),
        ("Month", "month"),
        ("Amount", "amount"),
    ),
    "v2021dec": (
        ("Organisation Code", "organisation_code"),
        ("Organisation Name", "organisation_name"),
        ("Control Budget", "control_budget_code"),
        ("Control Budget Detail", "control_budget_detail_code"),
        ("Department", "department_name"),
        ("Sub-segment Code", "sub_segment_code"),
        ("Sub-segment Name", "sub_segment_name"),
        ("Economic Category Code", "economic_category_code"),
        ("Economic Category Name", "economic_category_name"),
        ("Economic Budget", "economic_budget_code"),
        ("PESA Economic Group Code", "pesa_economic_group_code"),
        ("Version Snapshot", "version"),
        ("Year", "year"),
        ("Quarter", "quarter"),
        ("Month", "month"),
        ("Amount", "amount"),
    ),
    "v2023": (
        ("Organisation Code", "organisation_code"),
        ("Organisation", "organisation_name"),
        ("Control Budget Code", "control_budget_code"),
        ("Control Budget Detail Code", "control_budget_detail_code"),
        ("Segment Department Long Name", "department_name"),
        ("Sub Segment Code", "sub_segment_code"),
        ("Sub Segment Long Name", "sub_segment_name"),
        ("Economic Category Code", "economic_category_code"),
        ("Economic Category Long Name", "economic_category_name"),
        ("Economic Budget Code", "economic_budget_code"),
        ("PESA Economic Group Code", "pesa_economic_group_code"),
        ("Version", "version"),
        ("Year", "year"),
        ("Quarter", "quarter"),
        ("Month", "month"),
        ("Amount", "amount"),
    ),
}
_BY_HEADER = {tuple(src for src, _ in cols): name for name, cols in HEADER_VARIANTS.items()}

MONTHS = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
_MONTH_RE = re.compile(r"^([A-Za-z]{3})-(\d{2})$")
_YEAR_RE = re.compile(r"^(\d{4})-(\d{2})$")
_QUARTER_RE = re.compile(r"^Qtr([1-4]) - (\d{2})-(\d{2})$")

# Amount forms. Each pattern is tried in order on the stripped text; the first match names the form.
_NUM = r"\d+(?:\.\d+)?"
_GROUPED = r"\d{1,3}(?:,\d{3})+(?:\.\d+)?"
AMOUNT_FORMS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("plain", re.compile(rf"^-?{_NUM}$")),
    ("thousands_separator", re.compile(rf"^-?{_GROUPED}$")),
    ("scientific", re.compile(r"^-?\d+(?:\.\d+)?[eE][+-]?\d+$")),
    ("parentheses", re.compile(rf"^\((?:{_GROUPED}|{_NUM})\)$")),
    ("trailing_minus", re.compile(rf"^(?:{_GROUPED}|{_NUM})-$")),
)


class InyearFormatError(ValueError):
    """The file is not in a layout or format this reader knows. Never caught inside the reader."""


class InyearRow(NamedTuple):
    release: str
    line: int  # 1-based physical row in the sheet or record number in the CSV (header = 1)
    organisation_code: str
    organisation_name: str
    control_budget_code: str
    control_budget_detail_code: str
    department_name: str
    sub_segment_code: str
    sub_segment_name: str
    economic_category_code: str
    economic_category_name: str
    economic_budget_code: str
    pesa_economic_group_code: str
    pesa_economic_group_name: str  # '' outside the 2019 layout
    version: str
    year: str  # raw, e.g. '2022-23'
    quarter: str  # raw, e.g. 'Qtr1 - 22-23'
    month: str  # raw, e.g. 'Apr-22'
    amount_text: str  # raw text as stored (for ODS: the office:value attribute)
    amount: Decimal | None  # None only when the cell is blank
    amount_form: str
    financial_year: str  # derived from Month: '2022-23'; '' if Month is not a month
    period: int  # derived from Month: Apr = 1 ... Mar = 12; 0 if Month is not a month


@dataclass(frozen=True)
class InyearFile:
    """One fetched in-year data file as recorded in the manifest."""

    release: str
    filename: str
    path: str  # as in the manifest: repo-relative, or $UKFR_DATA_DIR/...
    sha256: str
    member: str  # zip member holding the data; '' for a bare file

    def resolve(self, repo_root: Path) -> Path:
        if self.path.startswith(RAW_PREFIX):
            return data_dir(repo_root) / self.path[len(RAW_PREFIX) :]
        return repo_root / self.path

    @property
    def container(self) -> str:
        """zip-csv, zip-ods, csv or ods."""
        inner = self.member or self.filename
        kind = "ods" if inner.lower().endswith(".ods") else "csv"
        return f"zip-{kind}" if self.member else kind


@dataclass
class ReadStats:
    """Facts gathered while reading one file; filled in by `read_inyear`."""

    header_variant: str = ""
    sheet: str = ""  # ODS only: the sheet holding the data
    other_sheets: list[str] = field(default_factory=list)
    bytes_read: int = 0  # size of the CSV text or the ODS file
    high_bytes: int = 0  # CSV: bytes >= 0x80
    high_byte_values: str = ""  # CSV: distinct high bytes, hex
    utf8_valid: bool | None = None  # CSV: would the bytes decode as UTF-8?
    line_ending: str = ""  # CSV: CRLF or LF (record terminator)
    physical_lines: int = 0  # CSV: lines in the text, header and blank lines included
    bare_lf: int = 0  # CSV: LF not preceded by CR, i.e. line breaks inside quoted fields
    total_rows: int = 0  # every row after the header, blank ones included
    blank_rows: int = 0
    blank_rows_trailing: int = 0  # the blank rows that come after the last data row
    data_rows: int = 0
    amount_forms: Counter = field(default_factory=Counter)
    stripped_fields: int = 0  # fields that had leading or trailing spaces
    month_unparsed: int = 0


def list_inyear_files(repo_root: Path) -> list[InyearFile]:
    """Every fetched in-year data file, sorted by release then file name."""
    out = []
    for r in read_rows(repo_root / FILES_CSV):
        if r.source_id != SOURCE_ID or r.fetched != "yes":
            continue
        name = r.filename.lower()
        if not name.endswith((".zip", ".csv", ".ods")):
            continue
        member = ""
        if name.endswith(".zip"):
            members = [m.split("|")[0] for m in r.zip_members.split(";") if m]
            data = [m for m in members if m.lower().endswith((".csv", ".ods"))]
            if len(data) != 1:
                raise InyearFormatError(f"{r.filename}: expected one CSV or ODS member, found {members}")
            member = data[0]
        out.append(InyearFile(r.release, r.filename, r.path, r.sha256, member))
    return sorted(out, key=lambda f: (f.release, f.filename))


def detect_variant(header: list[str], where: str) -> str:
    key = tuple(h.strip() for h in header)
    while key and not key[-1]:
        key = key[:-1]
    name = _BY_HEADER.get(key)
    if name is None:
        raise InyearFormatError(f"{where}: unknown header {list(key)}")
    return name


def parse_amount(text: str) -> tuple[Decimal | None, str]:
    """Exact value and the name of the form it was written in. Raises on anything unrecognised."""
    s = text.strip()
    if not s:
        return None, "blank"
    form = next((name for name, rx in AMOUNT_FORMS if rx.match(s)), None)
    if form is None:
        raise InyearFormatError(f"unrecognised amount {text!r}")
    if form == "parentheses":
        s = "-" + s[1:-1]
    elif form == "trailing_minus":
        s = "-" + s[:-1]
    try:
        # The constructor is exact whatever the context precision; arithmetic would not be.
        value = Decimal(s.replace(",", ""))
    except InvalidOperation as exc:  # pragma: no cover - the patterns above only admit valid numbers
        raise InyearFormatError(f"unrecognised amount {text!r}") from exc
    return value, form


def parse_month(text: str) -> tuple[str, int]:
    """'Apr-22' -> ('2022-23', 1); 'Mar-23' -> ('2022-23', 12). ('', 0) if it is not a month label."""
    m = _MONTH_RE.match(text.strip())
    if not m or m.group(1).title() not in MONTHS:
        return "", 0
    month = MONTHS.index(m.group(1).title()) + 1
    year = 2000 + int(m.group(2))
    start = year if month >= 4 else year - 1
    return f"{start}-{(start + 1) % 100:02d}", (month - 4) % 12 + 1


def parse_year(text: str) -> str:
    """'2022-23' -> '2022-23'; '' if it is not a financial-year label."""
    m = _YEAR_RE.match(text.strip())
    if not m or (int(m.group(1)) + 1) % 100 != int(m.group(2)):
        return ""
    return text.strip()


def parse_quarter(text: str) -> tuple[int, str]:
    """'Qtr1 - 22-23' -> (1, '2022-23'); (0, '') if it does not parse."""
    m = _QUARTER_RE.match(text.strip())
    if not m:
        return 0, ""
    return int(m.group(1)), f"20{m.group(2)}-{m.group(3)}"


def _open_bytes(f: InyearFile, repo_root: Path) -> bytes:
    path = f.resolve(repo_root)
    if f.member:
        with zipfile.ZipFile(path) as z:
            return z.read(f.member)
    return path.read_bytes()


def _csv_rows(data: bytes, where: str, stats: ReadStats) -> Iterator[list[str]]:
    stats.bytes_read = len(data)
    high = [b for b in data if b >= 0x80] if max(data, default=0) >= 0x80 else []
    stats.high_bytes = len(high)
    stats.high_byte_values = " ".join(f"{b:02X}" for b in sorted(set(high)))
    try:
        data.decode("utf-8")
        stats.utf8_valid = True
    except UnicodeDecodeError:
        stats.utf8_valid = False
    crlf = data.count(b"\r\n")
    stats.physical_lines = data.count(b"\n") + (0 if data.endswith(b"\n") or not data else 1)
    stats.bare_lf = data.count(b"\n") - crlf
    stats.line_ending = "CRLF" if crlf else "LF"
    try:
        text = data.decode(ENCODING)
    except UnicodeDecodeError as exc:
        raise InyearFormatError(f"{where}: not decodable as {ENCODING}: {exc}") from exc
    if text.startswith("﻿"):
        raise InyearFormatError(f"{where}: unexpected byte-order mark")
    yield from csv.reader(io.StringIO(text, newline=""))


def _ods_rows(data: bytes, where: str, stats: ReadStats) -> Iterator[tuple[list[str], list[str]]]:
    """(texts, kinds) per row of the one sheet whose first row is a known header."""
    stats.bytes_read = len(data)
    current = None
    for row in ods.iter_rows_from_bytes(data):
        if row.sheet != current:
            current = row.sheet
            texts = [c.text for c in row.cells]
            try:
                detect_variant(texts, where)
            except InyearFormatError:
                stats.other_sheets.append(row.sheet)
                continue
            if stats.sheet:
                raise InyearFormatError(f"{where}: two sheets hold data ({stats.sheet!r}, {row.sheet!r})")
            stats.sheet = row.sheet
        if row.sheet != stats.sheet:
            continue
        for _ in range(row.repeat):
            yield [c.text for c in row.cells], [c.kind for c in row.cells]
    if not stats.sheet:
        raise InyearFormatError(f"{where}: no sheet starts with a known header (sheets: {stats.other_sheets})")


def read_inyear(
    f: InyearFile, repo_root: Path, stats: ReadStats | None = None, lenient: bool = False
) -> Iterator[InyearRow]:
    """Yield the canonical rows of one in-year file. Pass a `ReadStats` to collect file facts.

    With `lenient=True` a row whose Amount cannot be read exactly is yielded with `amount=None` and
    `amount_form='unparseable'` instead of raising, so a loader can quarantine it. Headers that are
    not recognised still raise.
    """
    stats = stats if stats is not None else ReadStats()
    where = f"{f.release}/{f.member or f.filename}"
    data = _open_bytes(f, repo_root)
    is_ods = f.container.endswith("ods")
    if is_ods:
        source = _ods_rows(data, where, stats)
    else:
        source = ((r, None) for r in _csv_rows(data, where, stats))
    yield from _rows(source, f.release, where, stats, is_ods, lenient)


def read_inyear_bytes(
    data: bytes, release: str, kind: str = "csv", stats: ReadStats | None = None, lenient: bool = False
):
    """Same as `read_inyear` for bytes already in memory (`kind` 'csv' or 'ods'). Used by tests."""
    stats = stats if stats is not None else ReadStats()
    where = f"{release}/<bytes>"
    if kind == "ods":
        source = _ods_rows(data, where, stats)
    else:
        source = ((r, None) for r in _csv_rows(data, where, stats))
    yield from _rows(source, release, where, stats, kind == "ods", lenient)


def _rows(
    source, release: str, where: str, stats: ReadStats, is_ods: bool, lenient: bool = False
) -> Iterator[InyearRow]:
    header = None
    width = 0
    index: dict[str, int] = {}
    pending_blank = 0
    line = 0
    for cells, kinds in source:
        line += 1
        if header is None:
            stats.header_variant = detect_variant(cells, where)
            header = HEADER_VARIANTS[stats.header_variant]
            width = len(header)
            index = {canon: i for i, (_, canon) in enumerate(header)}
            continue
        stats.total_rows += 1
        if not any(c.strip() for c in cells):
            stats.blank_rows += 1
            pending_blank += 1
            continue
        pending_blank = 0
        if len(cells) > width and any(c.strip() for c in cells[width:]):
            raise InyearFormatError(f"{where} line {line}: {len(cells)} fields, header has {width}")
        cells = list(cells[:width]) + [""] * (width - len(cells))
        values = {}
        for canon, i in index.items():
            raw = cells[i]
            v = raw.strip()
            if v != raw:
                stats.stripped_fields += 1
            values[canon] = v
        amount_text = values["amount"]
        try:
            amount, form = parse_amount(amount_text)
        except InyearFormatError as exc:
            if not lenient:
                raise InyearFormatError(f"{where} line {line}: {exc}") from exc
            amount, form = None, "unparseable"
        if is_ods and kinds is not None:
            kind = kinds[index["amount"]] if index["amount"] < len(kinds) else ""
            form = f"ods_{kind}_{form}" if kind else f"ods_empty_{form}"
        stats.amount_forms[form] += 1
        fy, period = parse_month(values["month"])
        if not period:
            stats.month_unparsed += 1
        stats.data_rows += 1
        yield InyearRow(
            release,
            line,
            values["organisation_code"],
            values["organisation_name"],
            values["control_budget_code"],
            values["control_budget_detail_code"],
            values["department_name"],
            values["sub_segment_code"],
            values["sub_segment_name"],
            values["economic_category_code"],
            values["economic_category_name"],
            values["economic_budget_code"],
            values["pesa_economic_group_code"],
            values.get("pesa_economic_group_name", ""),
            values["version"],
            values["year"],
            values["quarter"],
            values["month"],
            amount_text,
            amount,
            form,
            fy,
            period,
        )
    if header is None:
        raise InyearFormatError(f"{where}: empty file")
    stats.blank_rows_trailing = pending_blank
