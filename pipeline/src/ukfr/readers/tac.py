"""Reader for the NHS trust accounts consolidation (TAC) data files and the illustrative TAC files.

Each year NHS England publishes two data workbooks, one for NHS trusts and one for NHS foundation
trusts. Both hold the same five sheets: `Intro` (text), `List of providers`, `All data` (the long
table this reader loads) and two pivot sheets that are formulas over it. `All data` has one header row
and seven columns: provider name, worksheet name (`TAC02 SoCI`), table id, main code (`A02CY01`: sheet
02, current year, column 01), row number in the TAC form, sub code (`SCI0100A`, the line) and the value.
The value is in thousands of pounds. The header text differs between years (`OrganisationName` or
`Organisation Name`, `Total` or `Value number`), so headers are compared after lower-casing and
removing spaces, and anything that is not in the table below stops the load.

Sheets are streamed: a row is read, turned into text and a `Decimal`, and handed on, so a workbook of
900,000 rows never sits in memory as one grid. Numbers come from the sheet XML as text and are rounded
to 15 significant digits, which is what Excel shows (see `ukfr.readers.plans.excel_number`).

The reader loads the three statements (`TAC02` income statement, `TAC03` balance sheet, `TAC05` cash
flow) and only counts the rows of every other worksheet, so the inventory of what was left out is
exact. The illustrative file of each year is the form with no data: its statement sheets give each
line's description and expected sign, which the data files do not carry.
"""

from __future__ import annotations

import re
import zipfile
from collections import Counter
from collections.abc import Iterator
from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path
from xml.etree import ElementTree as ET

from ..config import FILES_CSV, data_dir
from ..manifest import RAW_PREFIX, read_rows
from . import plans as rp

SOURCE_ID = "tac"
NS = rp._NS

# worksheet code (first five characters of the sheet name) -> statement
STATEMENTS = {"TAC02": "SoCI", "TAC03": "SoFP", "TAC05": "SoCF"}

# header text (lower case, spaces removed) -> canonical column; the file has exactly these seven
DATA_HEADERS = {
    "organisationname": "organisation_name",
    "worksheetname": "worksheet_name",
    "tableid": "table_id",
    "maincode": "main_code",
    "rownumber": "row_number",
    "subcode": "sub_code",
    "total": "value",
    "valuenumber": "value",
}
DATA_COLUMNS = (
    "organisation_name",
    "worksheet_name",
    "table_id",
    "main_code",
    "row_number",
    "sub_code",
    "value",
)
PROVIDER_HEADERS = {
    "fullnameofprovider": "provider_name",
    "nhscode": "nhs_code",
    "authorisationdate": "authorisation_date",
    "region": "region",
    "sector": "sector",
    "comments": "comments",
}
PROVIDER_COLUMNS = ("provider_name", "nhs_code", "authorisation_date", "region", "sector", "comments")

SUBCODE_RE = re.compile(r"^[A-Z]{3}\d{4}[A-Z]?$")
MAIN_CODE_RE = re.compile(r"^A(\d{2})(CY|PY)(\d{2})$")
WORKSHEET_RE = re.compile(r"^(TAC\d{2}[A-Z]?)\b")


class TacFormatError(ValueError):
    """The workbook is not in the layout this reader knows."""


@dataclass(frozen=True)
class TacFile:
    release: str  # '2024-25'
    filename: str
    path: str  # as in the manifest
    sha256: str

    @property
    def kind(self) -> str:
        return "template" if "llustrative" in self.filename or "ilustrative" in self.filename else "data"

    @property
    def provider_type(self) -> str:
        """NHS trust or NHS foundation trust, from the file name; empty for a template."""
        if self.kind != "data":
            return ""
        return "NHS foundation trust" if "foundation" in self.filename.lower() else "NHS trust"

    def resolve(self, repo_root: Path) -> Path:
        if self.path.startswith(RAW_PREFIX):
            return data_dir(repo_root) / self.path[len(RAW_PREFIX) :]
        return repo_root / self.path


@dataclass(frozen=True, slots=True)
class TacRow:
    line: int  # row number in the `All data` sheet (header = 1)
    values: tuple[str, ...]  # DATA_COLUMNS in order, as text; the value is the last
    amount: Decimal | None


@dataclass
class TacStats:
    total_rows: int = 0
    blank_rows: int = 0
    data_rows: int = 0  # every non-blank row of `All data`
    statement_rows: int = 0  # the rows handed on (the three statements)
    sheets: list[str] = field(default_factory=list)
    header: tuple[str, ...] = ()
    worksheet_rows: Counter = field(default_factory=Counter)  # worksheet name -> rows, all worksheets


def list_tac_files(repo_root: Path) -> list[TacFile]:
    """Every fetched TAC workbook in the manifest, data or template, in (release, kind, file name) order."""
    out = [
        TacFile(r.release, r.filename, r.path, r.sha256)
        for r in read_rows(repo_root / FILES_CSV)
        if r.source_id == SOURCE_ID and r.fetched == "yes" and r.filename.lower().endswith(".xlsx")
    ]
    return sorted(out, key=lambda f: (f.release, f.kind, f.filename))


def _plain(v) -> str:
    """A cell as text: a Decimal as digits with no trailing zeros, a string stripped."""
    if v is None:
        return ""
    if isinstance(v, Decimal):
        s = format(v, "f")
        if "." in s:
            s = s.rstrip("0").rstrip(".")
        return "0" if s in ("", "-0") else s
    return " ".join(str(v).replace("\xa0", " ").split())


def _norm_header(v) -> str:
    return re.sub(r"\s+", "", _plain(v)).lower()


def _shared_strings(z: zipfile.ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in z.namelist():
        return []
    root = ET.fromstring(z.read("xl/sharedStrings.xml"))
    return [rp._text(si) for si in root.iter(f"{NS}si")]


def iter_sheet(path: Path, sheet: str) -> Iterator[tuple[int, dict[int, object]]]:
    """Stream one sheet as (row number, {column index: value}); a numeric cell is a `Decimal`.

    Only non-empty cells appear in the dict. Rows come in file order, which is row order.
    """
    with zipfile.ZipFile(path) as z:
        parts = rp._sheet_paths(z)
        if sheet not in parts:
            raise TacFormatError(f"{path.name}: no sheet named {sheet!r}")
        shared = _shared_strings(z)
        with z.open(parts[sheet]) as f:
            cells: dict[int, object] = {}
            for _ev, el in ET.iterparse(f):
                if el.tag == f"{NS}c":
                    m = rp._CELL_RE.match(el.get("r", ""))
                    if m:
                        t = el.get("t", "n")
                        v = el.find(f"{NS}v")
                        val: object = None
                        if t == "s" and v is not None:
                            val = shared[int(v.text)]
                        elif t == "inlineStr":
                            is_ = el.find(f"{NS}is")
                            val = rp._text(is_) if is_ is not None else ""
                        elif t in ("str", "e") and v is not None:
                            val = v.text or ""
                        elif t == "b" and v is not None:
                            val = v.text
                        elif v is not None and v.text is not None:
                            val = rp.excel_number(v.text)
                        if val is not None and val != "":
                            cells[rp._col_index(m.group(1))] = val
                    el.clear()
                elif el.tag == f"{NS}row":
                    yield int(el.get("r", "0")), cells
                    cells = {}
                    el.clear()


def worksheet_code(name: str) -> str:
    """`TAC02 SoCI` -> `TAC02`; `TAC14A RoU Assets` -> `TAC14A`. Anything else is a format error."""
    m = WORKSHEET_RE.match(name.strip().upper())
    if not m:
        raise TacFormatError(f"worksheet name {name!r} does not start with a TAC form code")
    return m.group(1)


def _find_sheet(names: list[str], wanted: str, where: str) -> str:
    hits = [n for n in names if " ".join(n.split()).lower() == wanted]
    if len(hits) != 1:
        raise TacFormatError(f"{where}: expected one sheet named {wanted!r}, found {hits} in {names}")
    return hits[0]


def read_data(f: TacFile, repo_root: Path, stats: TacStats | None = None) -> Iterator[TacRow]:
    """The statement rows of one data workbook (see the module doc). `stats` is filled as it runs."""
    stats = stats if stats is not None else TacStats()
    where = f.filename
    path = f.resolve(repo_root)
    stats.sheets = rp.sheet_names(path)
    sheet = _find_sheet(stats.sheets, "all data", where)
    header_seen = False
    col_of: dict[int, str] = {}
    for line, cells in iter_sheet(path, sheet):
        if not header_seen:
            if not cells:
                continue
            header_seen = True
            if line != 1:
                raise TacFormatError(f"{where}: the header is on row {line}, not row 1")
            names = [_norm_header(cells.get(i)) for i in range(max(cells) + 1)]
            try:
                col_of = {i: DATA_HEADERS[n] for i, n in enumerate(names)}
            except KeyError as exc:
                raise TacFormatError(f"{where}: unknown header {exc.args[0]!r} in {names}") from None
            if tuple(col_of.get(i) for i in range(len(DATA_COLUMNS))) != DATA_COLUMNS:
                raise TacFormatError(f"{where}: header is not the seven TAC columns: {names}")
            stats.header = tuple(_plain(cells.get(i)) for i in range(len(DATA_COLUMNS)))
            continue
        stats.total_rows += 1
        if not cells:
            stats.blank_rows += 1
            continue
        if max(cells) >= len(DATA_COLUMNS):
            raise TacFormatError(f"{where} row {line}: data beyond column {len(DATA_COLUMNS)}")
        texts = tuple(_plain(cells.get(i)) for i in range(len(DATA_COLUMNS)))
        stats.data_rows += 1
        ws = texts[1]
        stats.worksheet_rows[ws] += 1
        if STATEMENTS.get(worksheet_code(ws)) is None:
            continue
        value = cells.get(len(DATA_COLUMNS) - 1)
        if value is None:
            amount = None
        elif isinstance(value, Decimal):
            amount = value
        else:
            raise TacFormatError(f"{where} row {line}: value {value!r} is not a number")
        stats.statement_rows += 1
        yield TacRow(line, texts, amount)


@dataclass(frozen=True, slots=True)
class ProviderRow:
    line: int  # row in `List of providers` (header = 1)
    values: tuple[str, ...]  # PROVIDER_COLUMNS in order, as text ('' when the column is absent)


def read_providers(f: TacFile, repo_root: Path) -> list[ProviderRow]:
    """The `List of providers` sheet: provider name, NHS (ODS) code, region, sector, comment, and for
    foundation trusts the authorisation date. Stops at the first row with no provider name."""
    where = f.filename
    path = f.resolve(repo_root)
    sheet = _find_sheet(rp.sheet_names(path), "list of providers", where)
    col_of: dict[int, str] = {}
    out: list[ProviderRow] = []
    for line, cells in iter_sheet(path, sheet):
        if not col_of:
            if not cells:
                continue
            names = {i: _norm_header(v) for i, v in cells.items()}
            try:
                col_of = {i: PROVIDER_HEADERS[n] for i, n in names.items()}
            except KeyError as exc:
                raise TacFormatError(f"{where}: unknown provider-list header {exc.args[0]!r}") from None
            missing = {"provider_name", "nhs_code", "region", "sector", "comments"} - set(col_of.values())
            if missing:
                raise TacFormatError(f"{where}: provider list lacks {sorted(missing)}")
            continue
        by_name = {col_of[i]: _plain(v) for i, v in cells.items() if i in col_of}
        if not by_name.get("provider_name"):
            continue
        if set(cells) - set(col_of):
            raise TacFormatError(f"{where} row {line}: provider list has data beyond its header")
        out.append(ProviderRow(line, tuple(by_name.get(c, "") for c in PROVIDER_COLUMNS)))
    return out


def read_intro(f: TacFile, repo_root: Path) -> list[tuple[int, str]]:
    """The `Intro` sheet as (row, text) for every non-empty row; cells of a row are joined with a space."""
    path = f.resolve(repo_root)
    sheet = _find_sheet(rp.sheet_names(path), "intro", f.filename)
    return [
        (line, " ".join(_plain(cells[i]) for i in sorted(cells))) for line, cells in iter_sheet(path, sheet) if cells
    ]


@dataclass(frozen=True, slots=True)
class TemplateRow:
    worksheet: str  # `TAC03 SoFP`
    line: int  # row in the sheet (1-based)
    table_id: str  # the `Table ID` block the row is under ('' before the first)
    label: str  # the line text as printed in the form
    expected_sign: str  # `+`, `-`, `+/-` or ''
    sub_code: str  # '' for a heading row
    main_cy: str  # the column codes of the block the row is under (`A03CY01`)
    main_py: str


def read_template(f: TacFile, repo_root: Path) -> list[TemplateRow]:
    """Every row of the three statement sheets of an illustrative file, in order, headings included.

    A `Table ID` marker starts a block; the main codes of its two value columns come from the header
    row that follows. Section structure is left to the SQL, which carries each heading forward.
    """
    path = f.resolve(repo_root)
    names = rp.sheet_names(path)
    out: list[TemplateRow] = []
    seen_codes: set[str] = set()
    for name in names:
        try:
            code = worksheet_code(name)
        except TacFormatError:
            continue
        if code not in STATEMENTS:
            continue
        seen_codes.add(code)
        table_id = ""
        mains: list[str] = []
        for line, cells in iter_sheet(path, name):
            texts = {i: _plain(v) for i, v in cells.items()}
            marker = [i for i, t in texts.items() if t == "Table ID"]
            if marker:
                nxt = texts.get(marker[0] + 1, "")
                table_id = nxt
                mains = []
                continue
            row_mains = [t for t in texts.values() if MAIN_CODE_RE.match(t)]
            if row_mains:
                mains = row_mains
                continue
            sub = [t for t in texts.values() if SUBCODE_RE.match(t)]
            signs = [t for t in texts.values() if t in ("+", "-", "+/-")]
            label_cols = sorted(i for i, t in texts.items() if i <= 2 and t and t not in ("+", "-", "+/-", "i"))
            label = texts[label_cols[0]] if label_cols else ""
            if (
                not label
                or label in ("NHS England", "Trust Accounts Consolidation Schedules", "Expected sign")
                or label == name.strip()
            ):
                continue
            if len(sub) > 1:
                raise TacFormatError(f"{f.filename} {name} row {line}: two sub codes {sub}")
            out.append(
                TemplateRow(
                    name.strip(),
                    line,
                    table_id,
                    label,
                    signs[0] if signs else "",
                    sub[0] if sub else "",
                    mains[0] if len(mains) > 0 else "",
                    mains[1] if len(mains) > 1 else "",
                )
            )
    if seen_codes != set(STATEMENTS):
        raise TacFormatError(
            f"{f.filename}: statement sheets found {sorted(seen_codes)}, expected {sorted(STATEMENTS)}"
        )
    return out
