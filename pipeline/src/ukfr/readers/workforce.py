"""Reader for the departmental workforce management information files (monthly, one file per
department and month, published on gov.uk).

The files come in four formats (csv, xlsx, xls, ods) and in the Cabinet Office "MWMI" templates, which
changed over time: a three-row header with merged group cells (older), a one-row header whose cells hold
the group, the item and the measure separated by semicolons or line breaks (newer), and different
non-payroll columns (agency, interim, specialist and consultant counts, then contingent-labour totals and a
count of consultancy contracts). A few files add spacing, case or punctuation changes to the same labels.

How a header is read, because it decides what a number means:

- The header block starts at the row that has `Organisation name` and ends at the first row whose first cell
  is a four-digit year. Group cells that were merged in a spreadsheet are filled to the right (an item is
  filled only while its group is unchanged), then the cells of one column are joined into one label.
- The label is lower-cased and reduced to letters, digits, `/`, `&` and spaces, then matched against the
  patterns in `MEASURE_PATTERNS`, which give each column a stable `measure_key`. A label that matches no
  pattern raises `WorkforceFormatError`; a label that matches two keys in one file does too. I do not guess.
- The text before the data (a title row, say) is ignored; text after the last data row is ignored only if it
  is blank.

How a value is read: a spreadsheet number becomes an exact `Decimal` (15 significant digits, the precision the
spreadsheet shows, as in `readers.plans`); a text cell is cleaned of `£`, thousands commas and surrounding
spaces (`"£1,877,791.41"` -> `1877791.41`). Blank cells are absent, never zero. A non-blank cell that is not a
number comes back as a value with `number=None`, and the loader quarantines it.

Amounts of money are in pounds (the template asks for monthly paybill in pounds); headcount and full-time
equivalent are people. Both are returned as published.
"""

from __future__ import annotations

import csv
import io
import re
from collections.abc import Iterator
from dataclasses import dataclass, field
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from pathlib import Path

from ..config import FILES_CSV, data_dir
from ..manifest import RAW_PREFIX
from ..manifest import read_rows as read_manifest
from . import ods
from . import plans as rp

SOURCE_ID = "workforce_mi"
RELEASE_RE = re.compile(r"^(?P<dept>[a-z0-9]+)-(?P<year>\d{4})-(?P<month>\d{2})$")
FORMATS = {".csv": "csv", ".xlsx": "xlsx", ".xls": "xls", ".ods": "ods"}

Cell = str | Decimal | None


class WorkforceFormatError(ValueError):
    """A file in a layout this reader does not know."""


# ---------------------------------------------------------------- the measure keys
#
# A normalised label is split into a scope (what the column is about), an item (which line of the template) and a
# kind (headcount, full-time equivalent, a count of contracts, or pounds). Each part is matched with `re.fullmatch`
# against the alternatives below, which are the wordings the files use. Anything else is an error.
#
# measure_key = <scope>_<item>_<kind>, for example `payroll_total_fte`, `np_contingent_total_hc`,
# `cost_payroll_paybill_gbp`.

_SCOPES = (
    # (pattern for the start of the label, scope); the first match wins, so the longer phrases come first
    (r"payroll staff costs", "cost"),
    (r"(?:number of )?non payroll(?: staff)?(?: \([^)]*\))?(?: costs)?", "np"),
    (r"payroll staff", "payroll"),
    (r"grand total \(workforce numbers\)", "grand"),
    (r"grand total paybill(?:/| and )staffing \(payroll and non payroll\) costs", "grand_cost"),
)
_PAYROLL_ITEMS = (
    ("ao_aa", r"ao/aa|aa/ao|admin officers/admin assistants"),
    ("eo", r"eo|executive officers"),
    ("seo_heo", r"seo/heo|heo/seo|higher executive officers/senior executive officers"),
    ("grade_6_7", r"grade 6/7"),
    ("scs", r"scs|senior civil service"),
    ("other", r"other unknown(?: or)? unspecified"),
    ("total", r"total(?: employees)?"),
)
_NP_ITEMS = (
    ("admin_clerical", r"admin and clerical"),
    ("interim_specialist", r"inter[a-z]+ mana?gers(?: and)? specialist contractors(?: and)? medical"),
    ("other_contingent", r"(?:non payroll staff )?other contingent labour"),
    ("contingent_total", r"total contingent labour"),
    ("agency", r"agency staff(?: \((?:clerical/admin|admin and clerical)\))?"),
    ("interim", r"inter[a-z]+ mana?gers"),
    ("specialist", r"specialist contractors"),
    ("consultants", r"consultants/consultancy|consultants"),
    ("total", r"total(?: employees)?"),
)
_COST_ITEMS = (
    ("salary", r"salary"),
    ("allowances", r"allowances"),
    ("non_consolidated", r"non consolidated performance payments"),
    ("overtime", r"overtime"),
    ("employer_pension", r"employer pension contributions"),
    ("employer_ni", r"employer national insurance contributions"),
    ("payroll_paybill", r"total paybill(?: for payroll staff)?"),
)
_NP_COST_ITEMS = (
    ("contingent", r"(?:total (?:monthly )?costs? of )?contingent labour.*|agency staff.* total monthly cost"),
    (
        "consultancy",
        r"(?:total (?:monthly )?costs? of )?consultants?/?consultancy(?: total monthly cost)?|consultancy|consultants",
    ),
    ("total", r"total staff costs|total non payroll \(ccl\) staff costs"),
    ("grand_total", r"paybill(?:/| and )staffing \(payroll and non payroll\) costs"),
)
_KINDS = (("hc", r"headcount"), ("fte", r"full time equivalent"))


def measure_key(label: str) -> str | None:
    """The measure key for a normalised label, or None when the label is not one the files are known to use."""
    for start, scope in _SCOPES:
        m = re.match(start + r"(?: |$)", label)
        if not m:
            continue
        rest = label[m.end() :].removesuffix(" excluding consultancy").removesuffix(" excludes consultants")
        if scope == "grand":
            return _kind_key("grand_total", rest) if rest in ("headcount", "full time equivalent") else None
        if scope == "grand_cost":
            return "cost_grand_total_gbp" if rest == "" else None
        if scope == "cost":
            return next((f"cost_{k}_gbp" for k, p in _COST_ITEMS if re.fullmatch(p, rest)), None)
        if scope == "np":
            for k, p in _NP_COST_ITEMS:
                if re.fullmatch(p, rest):
                    return f"cost_{'non_payroll_total' if k == 'total' else k}_gbp"
        items = _PAYROLL_ITEMS if scope == "payroll" else _NP_ITEMS
        if scope == "np" and re.fullmatch(
            r"(?:consultancy|consultants(?:/consultancy)?) number of (?:contracts|suppliers)", rest
        ):
            return "np_consultancy_contracts_n"
        for kind, kp in _KINDS:
            for item, ip in items:
                if re.fullmatch(rf"(?:{ip}) {kp}", rest):
                    return f"{scope}_{item}_{kind}"
        return None
    return None


def _kind_key(prefix: str, kind_text: str) -> str:
    return f"{prefix}_{'hc' if kind_text == 'headcount' else 'fte'}"


# The identifying columns, by normalised label.
ID_LABELS = {
    "year": "year",
    "month": "month",
    "organisation name": "organisation_name",
    "organisation type": "organisation_type",
    "main parent or sponsoring department": "parent_department",
}
# Columns that are neither identifiers nor measures and carry free text or nothing the model uses.
IGNORED_LABELS = ("comments", "comment", "notes", "note")
IGNORED_PREFIXES = ("comments", "notes for ")


# Misspellings I found in the published headers; each is a one-word fix that leaves the meaning beyond doubt.
_TYPOS = {"yotal": "total", "clarical": "clerical", "mangers": "managers", "intermin": "interim"}


def normalise(label: str) -> str:
    """Lower case; `&` becomes "and"; anything other than letters, digits, `/`, `(`, `)` becomes one space."""
    s = str(label).replace("\xa0", " ").replace("\u200b", "").lower().replace("-", " ")
    s = s.replace("&", " and ")
    s = re.sub(r"[^a-z0-9/()]+", " ", s)
    s = re.sub(r"\s*/\s*", "/", s)
    return " ".join(_TYPOS.get(word, word) for word in s.split())


# ---------------------------------------------------------------- numbers


# Pound signs as the files carry them: the sign itself, the same sign read as two characters (`Â£`), and the
# replacement character where a file lost the byte.
_CURRENCY = {"£", "Â", "�"}


def _strip_currency(s: str) -> str:
    return "".join(ch for ch in s if ch not in _CURRENCY)


_QUANTUM = Decimal("1e-4")


def settle(d: Decimal) -> Decimal:
    """A number is cut to 4 decimal places, the scale of dw.workforce_month. Spreadsheets
    store 16 or 17 digits of float noise (41534981.790000454, and 2.27e-13 where a sum should be 0); cutting at 4 places
    keeps what a department could have meant and gives the same number whether the noise was read from the file text
    or from the float the spreadsheet library returns."""
    return d.quantize(_QUANTUM, rounding=ROUND_HALF_UP)


def parse_number(text: str) -> Decimal | None:
    """`£1,877,791.41`, `-£3,066.35`, `(12.5)`, `7,500`, `0.00` -> Decimal; anything else -> None."""
    s = text.replace("\xa0", " ").strip()
    if not s:
        return None
    neg = False
    if s.startswith("(") and s.endswith(")"):
        neg, s = True, s[1:-1].strip()
    if s.startswith("-"):
        neg, s = True, s[1:].strip()
    s = _strip_currency(s).replace(",", "").strip()
    if s.startswith("-"):
        neg, s = True, s[1:].strip()
    if not re.fullmatch(r"\d+(?:\.\d+)?|\.\d+", s):
        return None
    try:
        d = rp.excel_number(s)
    except InvalidOperation:
        return None
    d = settle(d)
    return -d if neg else d


def cell_text(v: Cell) -> str:
    """A cell as the text I would store next to the number."""
    if v is None:
        return ""
    if isinstance(v, Decimal):
        s = format(v, "f")
        if "." in s:
            s = s.rstrip("0").rstrip(".")
        return "0" if s in ("", "-0") else s
    return str(v).strip()


# ---------------------------------------------------------------- grids: every format as rows of cells


def _from_float(v) -> Cell:
    if v is None or v == "":
        return None
    if isinstance(v, bool):
        return str(v)
    if isinstance(v, int):
        return Decimal(v)
    if isinstance(v, float):
        return rp.excel_number(repr(v))
    return str(v)


def grids_calamine(path: Path) -> dict[str, list[list[Cell]]]:
    """Every sheet of an xls (or any spreadsheet) as rows of cells, through python-calamine."""
    from python_calamine import CalamineWorkbook

    wb = CalamineWorkbook.from_path(str(path))
    out = {}
    for name in wb.sheet_names:
        rows = wb.get_sheet_by_name(name).to_python(skip_empty_area=False)
        out[name] = [[_from_float(c) for c in row] for row in rows]
    return out


def grids_ods(path: Path) -> dict[str, list[list[Cell]]]:
    out: dict[str, list[list[Cell]]] = {}
    with open(path, "rb") as fh:
        for row in ods.iter_rows(fh, max_cols=128):
            rows = out.setdefault(row.sheet, [])
            if row.blank:
                rows.extend([[] for _ in range(min(row.repeat, 50))])  # a long run of blanks is only a gap
                continue
            cells: list[Cell] = []
            for c in row.cells:
                if c.kind in ("float", "percentage", "currency") and c.text != "":
                    cells.append(rp.excel_number(c.text))
                else:
                    cells.append(c.text.strip() or None)
            rows.append(cells)
    return out


def grids_csv(path: Path) -> dict[str, list[list[Cell]]]:
    raw = path.read_bytes()
    for enc in ("utf-8-sig", "cp1252"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    rows = [[(c.strip() or None) for c in r] for r in csv.reader(io.StringIO(text, newline=""))]
    return {"csv": rows}


def read_grids(path: Path, fmt: str) -> dict[str, list[list[Cell]]]:
    if fmt == "csv":
        return grids_csv(path)
    if fmt == "xlsx":
        return rp.read_workbook(path)
    if fmt == "ods":
        return grids_ods(path)
    if fmt == "xls":
        return grids_calamine(path)
    raise WorkforceFormatError(f"{path.name}: format {fmt!r} is not read")


# ---------------------------------------------------------------- header and rows


@dataclass(frozen=True, slots=True)
class Column:
    index: int
    label: str  # the flattened header text as published (line breaks as spaces)
    key: str  # an id name from ID_LABELS values, or a measure key


@dataclass(frozen=True, slots=True)
class Value:
    column_index: int  # 0-based column in the sheet
    key: str
    column_label: str
    text: str
    number: Decimal | None  # None: the text is not a number


@dataclass(frozen=True, slots=True)
class WorkforceRow:
    line: int  # 1-based row in the sheet
    year: str
    month: str
    organisation_name: str
    organisation_type: str
    parent_department: str
    values: tuple[Value, ...]


@dataclass
class WorkforceStats:
    sheet: str = ""
    header_rows: int = 0
    header_line: int = 0
    total_rows: int = 0  # rows after the header block
    blank_rows: int = 0
    data_rows: int = 0
    columns: list[Column] = field(default_factory=list)
    ignored: list[tuple[int, str]] = field(default_factory=list)  # (column index, header) of comment and note columns
    template: str = ""


def _find_header(rows: list[list[Cell]]) -> int | None:
    for i, row in enumerate(rows[:40]):
        if any(normalise(cell_text(c)) == "organisation name" for c in row):
            return i
    return None


def _first_measure_column(row: list[Cell]) -> int | None:
    """The column after the last identifying column: 'Main, parent or sponsoring department', or 'Organisation type'
    in the files that have no parent column."""
    last = None
    for i, c in enumerate(row):
        n = normalise(cell_text(c))
        if n.startswith("main parent or sponsoring department") or n == "organisation type":
            last = i
    return None if last is None else last + 1


def _has_number(row: list[Cell], first: int) -> bool:
    for c in row[first:]:
        if isinstance(c, Decimal) or (c is not None and parse_number(cell_text(c)) is not None):
            return True
    return False


# ---------------------------------------------------------------- headers with no group row
#
# Some older files (BEIS, April 2018 to May 2021) were published with the group row, and often the identifier row,
# taken out: an item row (AO/AA, EO, ..., Salary, ...) over a row of Headcount and Full-time equivalent. The columns are
# in the template's order, so the group of each item follows from the item: the grades up to "Total Employees" are
# payroll; Agency, Interim, Specialist, Consultants and the plain "Total" are non-payroll; "Grand Total" is the grand
# total; the cost items follow the same way. The first three columns are the organisation name, type and parent. This
# is tried only when no header with a group row is found, and every label it builds still has to match `measure_key`.

_PAYROLL_WORDS = r"ao/aa|eo|seo/heo|grade 6/7|scs|other.*|total employees"
_NP_WORDS = r"agency staff.*|interim managers|specialist contractors|consultants/consultancy|total"
_PAYROLL_COST_WORDS = (
    r"salary|allowances|non consolidated performance payments|overtime|employer .*|total paybill for payroll staff"
)
_NP_COST_WORDS = r"total monthly costs? of .*|total non payroll \(ccl\) staff costs"
_GRAND_COST_WORDS = r"total (?:pay )?costs|grand total paybill.*|total pay costs"


def groupless_start(rows: list[list[Cell]]) -> int | None:
    """Index of the item row of a header that has no group row, or None."""
    for i, row in enumerate(rows[:12]):
        if i + 1 >= len(rows):
            return None
        items = [normalise(cell_text(c)) for c in row[3:]]
        kinds = [normalise(cell_text(c)) for c in rows[i + 1][3:]]
        has_group = any(normalise(cell_text(c)).startswith("payroll staff") for c in row)
        if "ao/aa" in items and "headcount" in kinds and not has_group:
            return i
    return None


def groupless_labels(item_row: list[Cell], kind_row: list[Cell], width: int) -> list[str]:
    """One label per column, built from the item and kind rows, in the wording of the group-row templates."""
    labels = ["Organisation name", "Organisation type", "Main, parent or sponsoring department"]
    labels += [""] * max(0, width - 3)
    item = ""
    for c in range(3, width):
        text = cell_text(item_row[c]) if c < len(item_row) else ""
        kind = cell_text(kind_row[c]) if c < len(kind_row) else ""
        if text:
            item = text
        elif not kind:
            continue
        n = normalise(item)
        if kind:
            if re.fullmatch(_PAYROLL_WORDS, n):
                shown = "Other, unknown, unspecified" if n.startswith("other") else item
                labels[c] = f"Payroll staff {shown} {kind}"
            elif re.fullmatch(_NP_WORDS, n):
                labels[c] = f"Number of non-payroll staff {item} {kind}"
            elif n == "grand total":
                labels[c] = f"Grand Total (workforce numbers) {kind}"
            else:
                labels[c] = f"{item} {kind}"  # not a known item: the measure key lookup will refuse it
        elif re.fullmatch(_PAYROLL_COST_WORDS, n):
            labels[c] = f"Payroll staff costs {item}"
        elif re.fullmatch(_NP_COST_WORDS, n):
            labels[c] = f"Non-payroll staff costs {item}"
        elif re.fullmatch(_GRAND_COST_WORDS, n):
            labels[c] = "Grand Total paybill/staffing (payroll and non-payroll) costs"
        else:
            labels[c] = item
    return labels


def _locate_with_groups(rows: list[list[Cell]]) -> tuple[int, int] | None:
    start = _find_header(rows)
    first = None if start is None else _first_measure_column(rows[start])
    if start is None or first is None:
        return None
    end = start + 1
    while end < len(rows) and not _has_number(rows[end], first):
        end += 1
        if end - start > 6:
            return None
    if end >= len(rows):
        return None
    has_group = any(normalise(cell_text(c)).startswith("payroll staff") for r in rows[start:end] for c in r)
    return (start, end) if has_group else None


def locate(rows: list[list[Cell]]) -> tuple[int, int, bool] | None:
    """(first header row, first data row, header has no group row) of the sheet, or None when it is not a data sheet.

    The header starts at the row that has 'Organisation name' and runs to the row before the first row that holds a
    number in a measure column. A data sheet's header mentions 'payroll staff'; the template's other sheets do not.
    A header with no group row is read by `groupless_labels`."""
    found = _locate_with_groups(rows)
    if found is not None:
        return (*found, False)
    i = groupless_start(rows)
    if i is None or i + 2 >= len(rows) or not _has_number(rows[i + 2], 3):
        return None
    return (i, i + 2, True)


def _header_text(v: Cell) -> str:
    """A header cell; a lone full stop is a filler some files put in the empty cells."""
    t = cell_text(v)
    return "" if t == "." else t


def _flatten_header(block: list[list[Cell]], width: int) -> list[str]:
    """One label per column. A group or item that was merged over several columns is filled to the right, but only
    through columns that have something on a lower header row, and an item only while the group above it is unchanged
    (a column with a group label and nothing below it, such as 'Grand Total paybill', is not filled into the blank
    columns that follow)."""
    n = len(block)
    cells = [[_header_text(r[c]) if c < len(r) else "" for c in range(width)] for r in block]
    if n == 1:
        return [" ".join(cells[0][c].split()) for c in range(width)]
    filled = [[""] * width for _ in range(n)]
    for level in range(n):
        last = ""
        for c in range(width):
            parent_changed = any(cells[p][c] for p in range(level))
            below = any(cells[q][c] for q in range(level + 1, n))
            if parent_changed and not cells[level][c]:
                last = ""
            if cells[level][c]:
                last = cells[level][c]
                filled[level][c] = last
            elif below:
                filled[level][c] = last
    out = []
    for c in range(width):
        parts = [filled[lv][c] for lv in range(n) if filled[lv][c]]
        out.append(" ".join(" ".join(parts).split()))
    return out


def parse_header(
    rows: list[list[Cell]], where: str, ignored: list[tuple[int, str]] | None = None
) -> tuple[int, int, list[Column], str]:
    """(header start index, header row count, columns, template name). Comment and note columns are not columns of
    the result; they are appended to `ignored` when it is given."""
    found = locate(rows)
    if found is None:
        raise WorkforceFormatError(f"{where}: no data header found")
    start, end, groupless = found
    block = rows[start:end]
    width = max(len(r) for r in block)
    if groupless:
        width = max(width, max((len(r) for r in rows[end : end + 3]), default=0))
        labels = groupless_labels(block[0], block[1], width)
    else:
        labels = _flatten_header(block, width)
    cols: list[Column] = []
    seen: dict[str, str] = {}
    for i, label in enumerate(labels):
        norm = normalise(label)
        if not norm:
            continue
        key = ID_LABELS.get(norm)
        if key is None and norm.startswith("main parent or sponsoring department"):
            key = "parent_department"
        if key is None:
            if norm in IGNORED_LABELS or norm.startswith(IGNORED_PREFIXES):
                if ignored is not None:
                    ignored.append((i, label))
                continue
            key = measure_key(norm)
        if key is None:
            raise WorkforceFormatError(f"{where}: unknown header in column {i + 1}: {label!r} (normalised {norm!r})")
        if key in seen:
            raise WorkforceFormatError(f"{where}: columns {seen[key]!r} and {label!r} both read as {key!r}")
        seen[key] = label
        cols.append(Column(i, label, key))
    if "organisation_name" not in seen:
        raise WorkforceFormatError(f"{where}: no organisation_name column")
    if ("year" in seen) != ("month" in seen):
        raise WorkforceFormatError(f"{where}: one of the Year and Month columns is missing")
    template = "no_group_row" if groupless else ("multi_row" if len(block) > 1 else "single_row")
    return start, len(block), cols, template


def read_sheet(rows: list[list[Cell]], where: str, stats: WorkforceStats) -> Iterator[WorkforceRow]:
    start, nhead, cols, template = parse_header(rows, where, stats.ignored)
    stats.header_line, stats.header_rows, stats.columns, stats.template = start + 1, nhead, cols, template
    ids = {c.key: c for c in cols if c.key in ID_LABELS.values()}
    measures = [c for c in cols if c.key not in ID_LABELS.values()]
    for i in range(start + nhead, len(rows)):
        raw = rows[i]
        stats.total_rows += 1
        if not any(cell_text(c) for c in raw):
            stats.blank_rows += 1
            continue

        def get(k: str, raw=raw) -> str:
            c = ids.get(k)
            return cell_text(raw[c.index]) if c is not None and c.index < len(raw) else ""

        values = []
        for c in measures:
            v = raw[c.index] if c.index < len(raw) else None
            text = cell_text(v)
            if not text:
                continue
            number = settle(v) if isinstance(v, Decimal) else parse_number(text)
            values.append(Value(c.index, c.key, c.label, text, number))
        year = get("year")
        if re.fullmatch(r"\d{4}\.0+", year):
            year = year.split(".")[0]
        stats.data_rows += 1
        yield WorkforceRow(
            i + 1,
            year,
            get("month"),
            " ".join(get("organisation_name").split()),
            get("organisation_type"),
            get("parent_department"),
            tuple(values),
        )


def pick_sheet(grids: dict[str, list[list[Cell]]], where: str) -> tuple[str, list[list[Cell]]]:
    """The one sheet that is a data sheet; none or several is an error."""
    found = [(n, r) for n, r in grids.items() if locate(r) is not None]
    if len(found) != 1:
        raise WorkforceFormatError(f"{where}: {len(found)} sheets look like the data sheet: {[n for n, _ in found]}")
    return found[0]


# ---------------------------------------------------------------- files


@dataclass(frozen=True)
class WorkforceFile:
    dept: str  # the collection's short id, from the release label (`dft`)
    month: str  # the month the file is published for, `2024-05`
    release: str
    filename: str
    path: str  # as in the manifest
    sha256: str

    @property
    def fmt(self) -> str:
        return FORMATS.get(Path(self.filename).suffix.lower(), "")

    def resolve(self, repo_root: Path) -> Path:
        if self.path.startswith(RAW_PREFIX):
            return data_dir(repo_root) / self.path[len(RAW_PREFIX) :]
        return repo_root / self.path


def list_workforce_files(repo_root: Path) -> list[WorkforceFile]:
    out = []
    for r in manifest_rows(repo_root):
        m = RELEASE_RE.match(r.release)
        if not m:
            raise WorkforceFormatError(f"release label {r.release!r} is not <dept>-<yyyy>-<mm>")
        out.append(WorkforceFile(m["dept"], f"{m['year']}-{m['month']}", r.release, r.filename, r.path, r.sha256))
    return sorted(out, key=lambda f: (f.dept, f.month, f.filename))


def manifest_rows(repo_root: Path):
    return [
        r
        for r in read_manifest(repo_root / FILES_CSV)
        if r.source_id == SOURCE_ID and r.fetched == "yes" and Path(r.filename).suffix.lower() in FORMATS
    ]


def read_workforce(f: WorkforceFile, repo_root: Path, stats: WorkforceStats | None = None) -> Iterator[WorkforceRow]:
    stats = stats if stats is not None else WorkforceStats()
    where = f"{f.dept} {f.month} {f.filename}"
    grids = read_grids(f.resolve(repo_root), f.fmt)
    stats.sheet, rows = pick_sheet(grids, where)
    yield from read_sheet(rows, where, stats)
