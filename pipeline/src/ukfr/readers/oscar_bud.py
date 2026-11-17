"""Reader for the OSCAR annual "BUD" workbooks (restated annual outturn, one financial year per file).

Each workbook holds one data sheet with a fixed 91-column header (`BUD_COLUMNS`). The reader checks
the header exactly and fails on anything else, returns every cell as text, and returns AMOUNT as an
exact `Decimal`.

Cells are read with python-calamine, which hands numbers back as IEEE doubles. A double that came
from a decimal string of at most 15 significant digits converts back to that same string with
`repr`, so `Decimal(repr(x))` reproduces the stored value exactly for such numbers. Every AMOUNT in
the 15 files I profiled is a whole number below 2**53 (the reader counts non-integral values, so a
future file that breaks this shows up in the stats rather than silently).
"""

from __future__ import annotations

from collections import Counter
from collections.abc import Iterator
from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path

from python_calamine import CalamineWorkbook

from ..config import FILES_CSV, data_dir
from ..manifest import RAW_PREFIX, read_rows
from .oscar_inyear import parse_amount

SOURCE_ID = "oscar_annual_bud"

BUD_COLUMNS = (
    "YEAR_NO", "YEAR_SHORT_NAME", "QUARTER_SHORT_NAME", "MONTH_SHORT_NAME", "BUDGETING_ORGANISATIONS_CODE",
    "DEPARTMENT_GROUP_CODE", "DEPARTMENT_GROUP_LONG_NAME", "ORGANISATION_CODE", "ORGANISATION_LONG_NAME",
    "ORGANISATION_TYPE_CODE", "ORGANISATION_TYPE_LONG_NAME", "ORGANISATION_TYPE_L1_CODE",
    "ORGANISATION_TYPE_L1_LONG_NAME", "PESA_GROUP_CODE", "PESA_GROUP_LONG_NAME", "SR_GROUP_CODE",
    "SR_GROUP_LONG_NAME", "BX_VALIDATION_GROUP_CODE", "BX_VALIDATION_GROUP_LONG_NAME", "FO_VALIDATION_GROUP_CODE",
    "FO_VALIDATION_GROUP_LONG_NAME", "ACCOUNTING_ARRANGEMENTS_CODE", "ACCOUNTING_ARRANGEMENTS_LONG_NAME",
    "COUNTER_ORGANISATION_CODE", "COUNTER_ORGANISATION_LONG_NAME", "SEGMENT_L4_CODE", "SEGMENT_L4_LONG_NAME",
    "COFOG_L0_CODE", "COFOG_L0_LONG_NAME", "COFOG_L1_CODE", "COFOG_L1_LONG_NAME", "COFOG_L2_CODE",
    "COFOG_L2_LONG_NAME", "CONTROL_BUDGET_L0_LONG_NAME", "CONTROL_BUDGET_L1_LONG_NAME", "COVERAGE_LONG_NAME",
    "ESTIMATES_ROW_CODE", "ESTIMATES_ROW_LONG_NAME", "NET_SUBHEAD_LONG_NAME", "PESA11_CODE", "PESA_LA_GRANTS_CODE",
    "PESA_LG_CODE", "PESA_SERVICES_LONG_NAME", "PESA_REGIONAL_CODE", "POLICY_RINGFENCE_CODE",
    "ACCOUNTING_AUTHORITY_L0_CODE", "ACCOUNTING_AUTHORITY_L1_LONG_NAME", "SUB_FUNCTION_CODE",
    "SUB_FUNCTION_LONG_NAME", "FUNCTION_CODE", "FUNCTION_LONG_NAME", "ACCOUNTS_LONG_NAME",
    "CHART_OF_ACCOUNTS_L5_CODE", "CHART_OF_ACCOUNTS_L5_LONG_NAME", "ECONOMIC_BUDGET_CODE", "ECONOMIC_RINGFENCE_CODE",
    "ECONOMIC_GROUP_CODE", "ECONOMIC_GROUP_LONG_NAME", "ECONOMIC_CATEGORY_CODE", "ECONOMIC_CATEGORY_LONG_NAME",
    "SECTOR_CODE", "SECTOR_LONG_NAME", "TES_CODE", "TES_LONG_NAME", "ESA_CODE", "ESA_LONG_NAME", "ESA_GROUP_CODE",
    "ESA_GROUP_LONG_NAME", "PSAT_CODE", "PSAT_LONG_NAME", "NA_AGGREGATE_CODE", "NA_AGGREGATE_LONG_NAME",
    "ESTIMATES_CATEGORY_CODE", "ESTIMATES_SUB_CATEGORY_CODE", "ESTIMATES_COLUMN_CODE", "PESA_ECONOMIC_BUDGET_CODE",
    "PESA_ECONOMIC_GROUP_CODE", "INCOME_CATEGORY_SHORT_NAME", "USAGE_CODE", "STATUS_CODE", "TYPE_CODE",
    "TYPE_LONG_NAME", "TYPE_GROUP_CODE", "TYPE_GROUP_LONG_NAME", "VERSION_CODE", "FCT_LOAD_TYPE_CODE",
    "FCT_LOAD_TYPE_LONG_NAME", "ROW_DESCRIPTION", "DATA_ID", "AMOUNT", "DATA_EFFECTIVE_DATETIME",
)  # fmt: skip
_AMOUNT = BUD_COLUMNS.index("AMOUNT")


class BudFormatError(ValueError):
    """The workbook is not in the layout this reader knows."""


@dataclass(frozen=True)
class BudFile:
    vintage: str  # release label of the annual publication, e.g. '2025-11'
    filename: str
    path: str  # as in the manifest
    sha256: str

    def resolve(self, repo_root: Path) -> Path:
        if self.path.startswith(RAW_PREFIX):
            return data_dir(repo_root) / self.path[len(RAW_PREFIX) :]
        return repo_root / self.path


@dataclass(frozen=True, slots=True)
class BudRow:
    vintage: str
    line: int  # 1-based row in the sheet (header = 1)
    values: dict[str, str]  # every column as text; whole-number cells without '.0'
    amount: Decimal | None
    amount_form: str

    def __getitem__(self, column: str) -> str:
        return self.values[column]

    @property
    def financial_year(self) -> str:
        """'202425' -> '2024-25'."""
        y = self.values["YEAR_NO"]
        return f"{y[:4]}-{y[4:]}" if len(y) == 6 else y


@dataclass
class BudStats:
    sheet: str = ""
    other_sheets: list[str] = field(default_factory=list)  # with the number of rows each holds
    total_rows: int = 0
    blank_rows: int = 0
    data_rows: int = 0
    amount_forms: Counter = field(default_factory=Counter)


def list_bud_files(repo_root: Path) -> list[BudFile]:
    out = []
    for r in read_rows(repo_root / FILES_CSV):
        if r.source_id == SOURCE_ID and r.fetched == "yes" and r.filename.upper().startswith("BUD"):
            out.append(BudFile(r.release, r.filename, r.path, r.sha256))
    return sorted(out, key=lambda f: (f.vintage, f.filename))


def _text(v) -> str:
    if v is None:
        return ""
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return str(int(v)) if v.is_integer() and abs(v) < 2**53 else repr(v)
    return str(v).strip()


def _amount(v) -> tuple[Decimal | None, str]:
    if isinstance(v, bool):
        raise BudFormatError(f"boolean amount {v!r}")
    if isinstance(v, int):
        return Decimal(v), "number_integral"
    if isinstance(v, float):
        if v.is_integer() and abs(v) < 2**53:
            return Decimal(int(v)), "number_integral"
        return Decimal(repr(v)), "number_fraction"
    if v is None or (isinstance(v, str) and not v.strip()):
        return None, "blank"
    value, form = parse_amount(str(v))
    return value, f"text_{form}"


def read_bud(f: BudFile, repo_root: Path, stats: BudStats | None = None) -> Iterator[BudRow]:
    stats = stats if stats is not None else BudStats()
    wb = CalamineWorkbook.from_path(str(f.resolve(repo_root)))
    yield from _read_workbook(wb, f.vintage, f.filename, stats)


def read_bud_workbook(wb: CalamineWorkbook, vintage: str, where: str, stats: BudStats | None = None):
    """Same as `read_bud` for an already opened workbook. Used by tests."""
    yield from _read_workbook(wb, vintage, where, stats if stats is not None else BudStats())


def _read_workbook(wb: CalamineWorkbook, vintage: str, where: str, stats: BudStats) -> Iterator[BudRow]:
    data_sheet = None
    for name in wb.sheet_names:
        rows = wb.get_sheet_by_name(name).to_python(skip_empty_area=False)
        header = tuple(_text(c) for c in rows[0]) if rows else ()
        while header and not header[-1]:
            header = header[:-1]
        if header == BUD_COLUMNS:
            if data_sheet is not None:
                raise BudFormatError(f"{where}: two data sheets ({stats.sheet!r}, {name!r})")
            data_sheet, stats.sheet = rows, name
        elif any(any(_text(c) for c in r) for r in rows):
            raise BudFormatError(
                f"{where}: sheet {name!r} holds data but its header is not the BUD layout: {list(header)[:8]}..."
            )
        else:
            stats.other_sheets.append(name)
    if data_sheet is None:
        raise BudFormatError(f"{where}: no sheet with the 91-column BUD header")
    width = len(BUD_COLUMNS)
    for i, raw in enumerate(data_sheet[1:], start=2):
        stats.total_rows += 1
        if len(raw) > width and any(_text(c) for c in raw[width:]):
            raise BudFormatError(f"{where} row {i}: data beyond column {width}")
        cells = list(raw[:width]) + [None] * (width - len(raw))
        texts = [_text(c) for c in cells]
        if not any(texts):
            stats.blank_rows += 1
            continue
        try:
            amount, form = _amount(cells[_AMOUNT])
        except ValueError as exc:
            raise BudFormatError(f"{where} row {i}: {exc}") from exc
        stats.amount_forms[form] += 1
        stats.data_rows += 1
        yield BudRow(vintage, i, dict(zip(BUD_COLUMNS, texts, strict=True)), amount, form)
