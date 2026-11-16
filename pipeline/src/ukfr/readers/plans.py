"""Read the plan sources: Estimates "Departmental DEL budgets" tables, PESA Chapter 1 tables and
the Spending Review 2025 DEL tables. Also the small exact xlsx cell reader the other readers use.

Numbers are read from the sheet XML as text and turned into `Decimal`, so no value passes through
float arithmetic. Excel writes a number as the shortest text that round-trips its double, which
can carry 16-17 significant digits (`16.128999999999998`); I round to 15 significant digits, the
precision Excel itself shows, which gives back the typed value (`16.129`). Strings come from the
shared-string table or inline strings.
"""

from __future__ import annotations

import re
import zipfile
from dataclasses import dataclass, field
from decimal import Context, Decimal
from pathlib import Path
from xml.etree import ElementTree as ET

_NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
_RNS = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
_PKG_RNS = "{http://schemas.openxmlformats.org/package/2006/relationships}"
_CELL_RE = re.compile(r"^([A-Z]+)(\d+)$")

Cell = str | Decimal | None
_EXCEL = Context(prec=15)


def excel_number(text: str) -> Decimal:
    """Cell value text -> Decimal at Excel's 15 significant digits, without trailing zeros."""
    d = _EXCEL.create_decimal(text)
    if d == d.to_integral_value():
        return d.quantize(Decimal(1))
    return d.normalize(_EXCEL)


def _col_index(letters: str) -> int:
    n = 0
    for ch in letters:
        n = n * 26 + (ord(ch) - 64)
    return n - 1


def _text(el) -> str:
    """Concatenate every <t> under a shared or inline string (rich text has several runs)."""
    return "".join(t.text or "" for t in el.iter(f"{_NS}t"))


def sheet_names(path: Path) -> list[str]:
    with zipfile.ZipFile(path) as z:
        wb = ET.fromstring(z.read("xl/workbook.xml"))
    return [s.get("name") for s in wb.iter(f"{_NS}sheet")]


def _sheet_paths(z: zipfile.ZipFile) -> dict[str, str]:
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
    target = {r.get("Id"): r.get("Target") for r in rels.iter(f"{_PKG_RNS}Relationship")}
    out = {}
    for s in wb.iter(f"{_NS}sheet"):
        t = target[s.get(f"{_RNS}id")]
        t = t.lstrip("/")
        out[s.get("name")] = t if t.startswith("xl/") else f"xl/{t}"
    return out


def read_workbook(path: Path, only: set[str] | None = None) -> dict[str, list[list[Cell]]]:
    """Every sheet as a dense list of rows. Numeric cells are Decimal, text cells str, blanks None."""
    out: dict[str, list[list[Cell]]] = {}
    with zipfile.ZipFile(path) as z:
        shared: list[str] = []
        if "xl/sharedStrings.xml" in z.namelist():
            root = ET.fromstring(z.read("xl/sharedStrings.xml"))
            shared = [_text(si) for si in root.iter(f"{_NS}si")]
        for name, part in _sheet_paths(z).items():
            if only is not None and name not in only:
                continue
            grid: dict[int, dict[int, Cell]] = {}
            with z.open(part) as f:
                for _ev, el in ET.iterparse(f):
                    if el.tag != f"{_NS}c":
                        continue
                    m = _CELL_RE.match(el.get("r", ""))
                    if not m:
                        el.clear()
                        continue
                    col, row = _col_index(m.group(1)), int(m.group(2)) - 1
                    t = el.get("t", "n")
                    v = el.find(f"{_NS}v")
                    val: Cell = None
                    if t == "s" and v is not None:
                        val = shared[int(v.text)]
                    elif t == "inlineStr":
                        is_ = el.find(f"{_NS}is")
                        val = _text(is_) if is_ is not None else ""
                    elif t in ("str", "e") and v is not None:
                        val = v.text or ""
                    elif t == "b" and v is not None:
                        val = v.text
                    elif v is not None and v.text is not None:
                        val = excel_number(v.text)
                    if val is not None and val != "":
                        grid.setdefault(row, {})[col] = val
                    el.clear()
            nrows = max(grid) + 1 if grid else 0
            ncols = max((max(r) for r in grid.values() if r), default=-1) + 1
            out[name] = [[grid.get(r, {}).get(c) for c in range(ncols)] for r in range(nrows)]
    return out


# ---------------------------------------------------------------- names

_FOOTNOTE_TAIL = re.compile(r"(?:\s*\(\d+\))+\s*$|(?<=[A-Za-z\)'])\d+(?:\s*,\s*\d+)*\s*$")


def clean_name(raw: str) -> str:
    """Strip footnote markers and stray whitespace: 'Home Office2' -> 'Home Office',
    'Scottish Government (1)' -> 'Scottish Government', 'MHCLG - Local Government ' -> 'MHCLG - Local Government'."""
    s = " ".join(str(raw).replace("\xa0", " ").split())
    s = re.sub(r"\s*\(\d{1,2}\)", "", s).strip().rstrip(",").strip()  # '(1)' markers, wherever they sit
    prev = None
    while prev != s:
        prev = s
        s = _FOOTNOTE_TAIL.sub("", s).strip()
    return s


def name_key(name: str) -> str:
    """A loose comparison key: lower case, '&' as 'and', punctuation and 'department for/of' dropped."""
    s = clean_name(name).lower().replace("&", " and ").replace("'", "").replace("’", "")
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    s = re.sub(r"\b(the|department|dept|for|of|group)\b", " ", s)
    return " ".join(s.split())


# ---------------------------------------------------------------- tables

_YEAR_RE = re.compile(r"^(\d{4})-(\d{2})$")


def _is_num(v: Cell) -> bool:
    return isinstance(v, Decimal)


def _str(v: Cell) -> str:
    return "" if v is None else str(v).strip()


@dataclass
class TableRow:
    row: int  # 0-based row in the sheet
    section: str
    raw_name: str
    name: str
    kind: str  # line | total | memo
    values: dict[str, Decimal | None]  # year label -> value (None for '-' or blank)


@dataclass
class Table:
    workbook: str
    sheet: str
    title: str
    unit: str
    unit_row: int
    year_row: int
    status_row: int | None
    years: list[str]
    statuses: dict[str, str]  # year -> 'plans' / 'outturn' / ''
    rows: list[TableRow] = field(default_factory=list)

    def lines(self, section_contains: str | None = None) -> list[TableRow]:
        return [
            r
            for r in self.rows
            if r.kind == "line" and (section_contains is None or section_contains.lower() in r.section.lower())
        ]


def _find_unit(rows: list[list[Cell]], upto: int) -> tuple[str, int]:
    for i, r in enumerate(rows[:upto]):
        for v in r:
            s = _str(v)
            if "£" in s or "�" in s:
                return s, i
    return "", -1


def parse_table(workbook: str, sheet: str, rows: list[list[Cell]]) -> Table | None:
    """Parse one HMT table sheet: a title, a unit cell, a row of year labels (`2022-23`), optionally a
    row of 'plans'/'outturn' labels (above or below the years), then line rows, section headings,
    totals and footnotes. Returns None if the sheet has no year row."""
    year_row = -1
    year_cols: dict[int, str] = {}
    for i, r in enumerate(rows[:12]):
        cols = {j: _str(v) for j, v in enumerate(r) if _YEAR_RE.match(_str(v))}
        if not cols:
            continue
        # one year column is enough if numbers follow below it within a few rows (Estimates tables)
        below = any(j < len(rows[k]) and _is_num(rows[k][j]) for j in cols for k in range(i + 1, min(i + 4, len(rows))))
        if len(cols) >= 2 or below:
            year_row, year_cols = i, cols
            break
    if year_row < 0:
        return None
    # keep the first run of year columns only (SR tables repeat short year labels further right)
    first = sorted(year_cols)
    run = [first[0]]
    for c in first[1:]:
        if c == run[-1] + 1:
            run.append(c)
        else:
            break
    year_cols = {c: year_cols[c] for c in run}
    status_row = None
    statuses = {y: "" for y in year_cols.values()}
    for k in (year_row + 1, year_row - 1):
        if 0 <= k < len(rows):
            labels = {c: _str(rows[k][c]).lower() if c < len(rows[k]) else "" for c in year_cols}
            if any(re.match(r"^(plans?|outturn|estimated outturn|forecast)", v) for v in labels.values()):
                status_row = k
                statuses = {year_cols[c]: re.sub(r"\d+$", "", v).strip() for c, v in labels.items()}
                break
    unit, unit_row = _find_unit(rows, year_row + 2)
    title = next((_str(v) for r in rows[:3] for v in r if _str(v)), "")
    t = Table(workbook, sheet, title, unit, unit_row, year_row, status_row, list(year_cols.values()), statuses)
    start = max(year_row, status_row if status_row is not None else -1) + 1
    section = ""
    name_cols = [c for c in range(min(year_cols))]
    # the column that holds line names: the leftmost text column on rows that carry numbers; a name
    # further right (Estimates' "o/w block grant adjustments") is a memo line inside the one above
    base = min(
        (
            next(c for c in name_cols if c < len(r) and _str(r[c]))
            for r in rows[start:]
            if any(c < len(r) and _str(r[c]) for c in name_cols)
            and any(c < len(r) and _is_num(r[c]) for c in year_cols)
        ),
        default=0,
    )
    for i in range(start, len(rows)):
        r = rows[i]
        vals = {y: (r[c] if c < len(r) else None) for c, y in year_cols.items()}
        texts = [(c, _str(r[c])) for c in name_cols if c < len(r) and _str(r[c])]
        has_num = any(_is_num(v) for v in vals.values())
        has_dash = any(_str(v) in ("-", "–", "..") for v in vals.values())
        if not texts:
            continue
        if not has_num and not has_dash:
            if len(texts[0][1]) < 120 and not re.match(r"^\(?\d", texts[0][1]):
                section = clean_name(texts[0][1])
            continue
        c0, raw = texts[0]
        lowered = raw.strip().lower()
        if c0 > base or lowered.startswith(("o/w", "of which")):
            kind = "memo"
        elif lowered.startswith("total"):
            kind = "total"
        else:
            kind = "line"
        # SR tables repeat the name in two columns; take the last text cell before the values
        if len(texts) > 1 and kind != "memo":
            raw = texts[-1][1] if clean_name(texts[-1][1]) == clean_name(texts[0][1]) else raw
        t.rows.append(
            TableRow(i, section, raw, clean_name(raw), kind, {y: (v if _is_num(v) else None) for y, v in vals.items()})
        )
    return t


def read_tables(path: Path) -> list[Table]:
    out = []
    for sheet, rows in read_workbook(path).items():
        t = parse_table(path.name, sheet, rows)
        if t is not None:
            out.append(t)
    return out


# ---------------------------------------------------------------- Estimates DEL tables

ESTIMATES_MEASURES = {
    # sheet title fragment -> measure code
    "excluding depreciation": "RDEL_EX_DEPN",
    "resource budgets": "RDEL",
    "capital budgets": "CDEL",
    "direct impact of tax changes": "RDEL_EX_DEPN_TAX_ALLOWANCE",
}


def estimates_measure(title: str) -> str:
    t = title.lower()
    if "tax changes" in t:
        return "RDEL_EX_DEPN_TAX_ALLOWANCE"
    if "excluding depreciation" in t:
        return "RDEL_EX_DEPN"
    if "resource" in t:
        return "RDEL"
    if "capital" in t:
        return "CDEL"
    return "UNKNOWN"


def unit_multiplier_to_thousands(unit: str) -> Decimal:
    """£ billion -> 1,000,000 (£000 per unit); £ million -> 1,000."""
    u = unit.lower()
    if "billion" in u:
        return Decimal(1_000_000)
    if "million" in u:
        return Decimal(1_000)
    if "thousand" in u or "000" in u:
        return Decimal(1)
    raise ValueError(f"unknown unit {unit!r}")
