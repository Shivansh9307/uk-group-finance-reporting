"""Read HM Treasury's GDP deflator workbooks and the ONS CPI time-series CSVs.

GDP deflator workbook (one sheet, named after the update date): a header block, then one row per
financial year with the index (`2025-26 = 100`), the per cent change on the previous year and money
GDP, and a calendar-year block to the right. Forecast years carry footnote markers in the year label
(`2026-27 (1), (2)`) and `-` in place of an index level: only the per cent change is given.

ONS CSV (generator output): key/value metadata lines (`"Title"`, `"CDID"`, `"Release date"` ...), then
annual rows (`"1989"`), quarterly rows (`"1989 Q1"`) and monthly rows (`"1989 JAN"`) in that order.
"""

from __future__ import annotations

import csv
import re
from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path

from .plans import Cell, read_workbook

_FY_RE = re.compile(r"^(\d{4}-\d{2})\s*(.*)$")


@dataclass
class DeflatorYear:
    year: str  # '2025-26'
    index: Decimal | None
    pct_change: Decimal | None
    money_gdp_nsa: Decimal | None
    money_gdp_sa: Decimal | None
    forecast: bool
    row: int


@dataclass
class GdpDeflator:
    sheet: str
    notes: list[str]
    base: str  # '2025-26 = 100'
    header_row: int
    years: list[DeflatorYear] = field(default_factory=list)

    @property
    def last_outturn(self) -> str:
        return [y.year for y in self.years if not y.forecast][-1]

    @property
    def first_forecast(self) -> str | None:
        f = [y.year for y in self.years if y.forecast]
        return f[0] if f else None

    def by_year(self) -> dict[str, DeflatorYear]:
        return {y.year: y for y in self.years}


def _s(v: Cell) -> str:
    return "" if v is None else str(v).strip()


def _num(v: Cell) -> Decimal | None:
    return v if isinstance(v, Decimal) else None


def read_gdp_deflator(path: Path) -> GdpDeflator:
    sheets = read_workbook(path)
    if len(sheets) != 1:
        raise ValueError(f"{path.name}: expected one sheet, found {list(sheets)}")
    sheet, rows = next(iter(sheets.items()))
    header, c_year = next(
        (i, j)
        for i, r in enumerate(rows[:15])
        for j, v in enumerate(r)
        if _s(v) == "Financial year" and any("= 100" in _s(x) for x in r)
    )
    h = rows[header]
    c_index = next(j for j, v in enumerate(h) if "= 100" in _s(v))
    c_pct = next(j for j, v in enumerate(h) if "per cent change" in _s(v).lower())
    money = [j for j, v in enumerate(h) if "£ million" in _s(v)]
    c_nsa = next((j for j in money if "non" in _s(h[j]).lower()), None)
    c_sa = next((j for j in money if j != c_nsa), None)
    notes = [_s(r[c_year]) for r in rows[:header] if len(r) > c_year and _s(r[c_year])]
    d = GdpDeflator(sheet, notes, _s(h[c_index]), header)
    for i in range(header + 1, len(rows)):
        r = rows[i]
        m = _FY_RE.match(_s(r[c_year]) if len(r) > c_year else "")
        if not m:
            if d.years:
                break
            continue

        def at(j, r=r):
            return r[j] if j is not None and j < len(r) else None

        idx = _num(at(c_index))
        d.years.append(
            DeflatorYear(
                year=m.group(1),
                index=idx,
                pct_change=_num(at(c_pct)),
                money_gdp_nsa=_num(at(c_nsa)),
                money_gdp_sa=_num(at(c_sa)),
                forecast=idx is None or bool(m.group(2)),
                row=i,
            )
        )
    return d


def chained_index(d: GdpDeflator, places: int = 4) -> dict[str, Decimal]:
    """Index levels for every year: the published outturn levels as they stand, and each forecast
    year chained from the year before with its published per cent change. Rounded to `places`
    decimal places (the workbook publishes four) only at the end of each step."""
    q = Decimal(1).scaleb(-places)
    out: dict[str, Decimal] = {}
    prev: Decimal | None = None
    for y in d.years:
        if not y.forecast and y.index is not None:
            level = y.index
        else:
            if prev is None or y.pct_change is None:
                raise ValueError(f"cannot chain {y.year}: no previous level or no per cent change")
            level = (prev * (1 + y.pct_change / 100)).quantize(q)
        out[y.year] = level
        prev = level
    return out


# ---------------------------------------------------------------- ONS time series CSV

_ANNUAL = re.compile(r"^\d{4}$")
_QUARTER = re.compile(r"^\d{4} Q[1-4]$")
_MONTH = re.compile(r"^\d{4} (JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)$")
MONTHS = ("JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC")


@dataclass
class OnsSeries:
    meta: dict[str, str]
    annual: list[tuple[str, Decimal]]
    quarterly: list[tuple[str, Decimal]]
    monthly: list[tuple[str, Decimal]]
    first_data_line: int
    block_starts: dict[str, int]  # 'annual'/'quarterly'/'monthly' -> 1-based line number

    @property
    def latest_month(self) -> str:
        return self.monthly[-1][0]


def month_key(label: str) -> tuple[int, int]:
    """'2026 SEP' -> (2026, 9)."""
    y, m = label.split()
    return int(y), MONTHS.index(m) + 1


def read_ons_series(path: Path) -> OnsSeries:
    """Split an ONS generator CSV into its blocks by the shape of the first column, not by position:
    the number of metadata lines has changed between downloads before."""
    meta: dict[str, str] = {}
    blocks: dict[str, list[tuple[str, Decimal]]] = {"annual": [], "quarterly": [], "monthly": []}
    starts: dict[str, int] = {}
    first = 0
    with open(path, encoding="utf-8-sig", newline="") as f:
        for n, row in enumerate(csv.reader(f), start=1):
            if not row:
                continue
            key = row[0].strip()
            val = row[1].strip() if len(row) > 1 else ""
            kind = (
                "annual"
                if _ANNUAL.match(key)
                else "quarterly"
                if _QUARTER.match(key)
                else "monthly"
                if _MONTH.match(key)
                else None
            )
            if kind is None:
                if first:
                    raise ValueError(f"{path.name} line {n}: unexpected row {row!r} after data started")
                meta[key] = val
                continue
            if not first:
                first = n
            starts.setdefault(kind, n)
            blocks[kind].append((key, Decimal(val)))
    order = [starts[k] for k in ("annual", "quarterly", "monthly") if k in starts]
    if order != sorted(order):
        raise ValueError(f"{path.name}: blocks out of the expected annual/quarterly/monthly order")
    keys = [month_key(k) for k, _ in blocks["monthly"]]
    if keys != sorted(keys) or len(set(keys)) != len(keys):
        raise ValueError(f"{path.name}: monthly block is not strictly increasing")
    return OnsSeries(meta, blocks["annual"], blocks["quarterly"], blocks["monthly"], first, starts)
