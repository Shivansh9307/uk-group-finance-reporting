"""Load stage for the departments' monthly forecast returns (scope full: the files are not in git).

83 returns, FY2017-18 to FY2022-23. FY2017-18 to FY2020-21 come from the November 2022 annual
extracts (one pipe-delimited member per year holding the returns R0 to R13 in `VERSION_CODE`; Deflate64,
streamed through `ukfr.readers.oscar_extract`, never written to disk). FY2021-22 and FY2022-23 come from the
two MFO zips (one csv per return, `ukfr.readers.oscar_mfo`). The FY2021-22 extract is not read: it holds
R13 and the plans only, and the MFO zip has R01 to R13 of the same year.

Lands, untyped and without any business rule:

- `raw.forecast_return_file`  one row per member read (an extract member, or one MFO return csv)
- `raw.forecast_return_cell`  the member's data rows added up at
  return x month x status x type x department group x Spending Review group x organisation x economic
  category x control budget (both names as written) x economic budget. Everything the load grain needs is in
  the key; the columns the grain drops (sub-segment, chart of accounts, usage, the accounts label and about
  eighty descriptive columns) are summed over. Amounts are added as exact `Decimal`s, so a cell holds the
  exact sum of its source rows; `source_rows`, `first_line` and `last_line` carry the lineage (the data
  record number inside the member, first data row = 1). Period 0 rows are loaded and kept.
- `raw.forecast_return_expected`  the independent recomputation `data/audit/forecast_independent_control.csv`

The business rules (which months are actual, the status and quality flags, the organisation key, the
own forecast and the accuracy) are T-SQL under `sql/`.
"""

from __future__ import annotations

import csv
import sys
import time
from collections.abc import Iterator
from dataclasses import dataclass
from decimal import Decimal, localcontext
from pathlib import Path

from ..manifest import Row
from ..readers import oscar_extract as rx
from ..readers import oscar_mfo as rm
from . import Stage, StageContext
from .oscar_inyear import file_sha256
from .plans import manifest_files

INDEPENDENT_CSV = Path("data") / "audit" / "forecast_independent_control.csv"
EXTRACT_YEARS = ("2017-18", "2018-19", "2019-20", "2020-21")  # the 2021-22 extract has R13 only: MFO is used
AMOUNT_SCALE = 16  # raw.forecast_return_cell.amount is DECIMAL(38,16): MFO has amounts such as 1.00E-13

FILE_COLUMNS = (
    "file_id",
    "family",
    "source_id",
    "release",
    "filename",
    "member",
    "financial_year",
    "return_no",
    "sha256_manifest",
    "sha256_file",
    "source_rows",
    "repaired_records",
    "cells",
)
CELL_COLUMNS = (
    "file_id",
    "cell_id",
    "return_no",
    "period",
    "status_code",
    "type_code",
    "department_group_code",
    "department_group_name",
    "sr_group_code",
    "organisation_code",
    "organisation_name",
    "economic_category_code",
    "control_budget_l0_name",
    "control_budget_l1_name",
    "economic_budget_code",
    "amount",
    "source_rows",
    "first_line",
    "last_line",
)
EXPECTED_COLUMNS = ("family", "financial_year", "return_no", "period", "data_rows", "amount_sum")

KEY_COLUMNS = (
    "return_no",
    "period",
    "status_code",
    "type_code",
    "department_group_code",
    "sr_group_code",
    "organisation_code",
    "economic_category_code",
    "control_budget_l0_name",
    "control_budget_l1_name",
    "economic_budget_code",
)
_SOURCE_COLUMNS = (
    "STATUS_CODE",
    "TYPE_CODE",
    "DEPARTMENT_GROUP_CODE",
    "SR_GROUP_CODE",
    "ORGANISATION_CODE",
    "ECONOMIC_CATEGORY_CODE",
    "CONTROL_BUDGET_L0_LONG_NAME",
    "CONTROL_BUDGET_L1_LONG_NAME",
    "ECONOMIC_BUDGET_CODE",
)


@dataclass
class Cell:
    """One cell while it is being added up; the descriptive names are the first seen."""

    amount: Decimal
    rows: int
    first_line: int
    last_line: int
    department_group_name: str
    organisation_name: str


def check_scale(amount: Decimal, where: str) -> None:
    """A value like 1.00E-13 has exponent -15 but only 13 decimal places: compare with the rounded value."""
    with localcontext() as ctx:
        ctx.prec = 80
        if amount.quantize(Decimal(1).scaleb(-AMOUNT_SCALE)) != amount:
            raise ValueError(f"{where}: amount {amount} has more than {AMOUNT_SCALE} decimal places")


def add_row(cells: dict[tuple, Cell], key: tuple, amount: Decimal, line: int, dg_name: str, org_name: str) -> None:
    c = cells.get(key)
    if c is None:
        cells[key] = Cell(amount, 1, line, line, dg_name, org_name)
    else:
        c.amount += amount
        c.rows += 1
        c.last_line = line


def extract_cells(path: Path, member: str) -> tuple[dict[int, dict[tuple, Cell]], dict[int, int], int]:
    """Stream one annual extract; cells per return, source rows per return, rows read.

    Rows whose VERSION_CODE is not R0..R13 (the plans) are counted as read and skipped."""
    by_return: dict[int, dict[tuple, Cell]] = {}
    rows_per_return: dict[int, int] = {}
    intern = sys.intern
    read = 0
    with rx.open_extract(path, member) as (header, ix, rows):
        cols = [ix[c] for c in _SOURCE_COLUMNS]
        i_ver, i_month, i_amt = ix["VERSION_CODE"], ix["MONTH_SHORT_NAME"], ix["AMOUNT"]
        i_dgn, i_orn = ix["DEPARTMENT_GROUP_LONG_NAME"], ix["ORGANISATION_LONG_NAME"]
        ncol = len(header)
        for line, row in enumerate(rows, start=1):
            read += 1
            if len(row) != ncol:
                raise ValueError(f"{path.name} record {line}: {len(row)} fields, expected {ncol}")
            ver = row[i_ver]
            if not (ver.startswith("R") and ver[1:].isdigit()):
                continue
            ret = int(ver[1:])
            amount = rx.parse_amount(row[i_amt])
            period = rx.month_period(row[i_month])
            vals = [intern(row[c].strip()) for c in cols]
            cells = by_return.setdefault(ret, {})
            rows_per_return[ret] = rows_per_return.get(ret, 0) + 1
            check_scale(amount, f"{path.name} record {line}")
            add_row(cells, (period, *vals), amount, line, row[i_dgn].strip(), row[i_orn].strip())
    return by_return, rows_per_return, read


def mfo_cells(path: Path, member: str) -> tuple[dict[tuple, Cell], int, int]:
    """Stream one MFO return csv; cells, data records read, records rebuilt from two pieces."""
    cells: dict[tuple, Cell] = {}
    intern = sys.intern
    read = 0
    stats = rm.RepairStats()
    with rm.open_return(path, member, stats) as (header, ix, rows):
        cols = [ix[c] for c in _SOURCE_COLUMNS]
        i_month, i_amt = ix["MONTH_SHORT_NAME"], ix["AMOUNT"]
        i_dgn, i_orn = ix["DEPARTMENT_GROUP_LONG_NAME"], ix["ORGANISATION_LONG_NAME"]
        ncol = len(header)
        for line, row in enumerate(rows, start=1):
            read += 1
            if len(row) != ncol:
                raise ValueError(f"{member} record {line}: {len(row)} fields, expected {ncol}")
            amount = rm.parse_amount(row[i_amt])
            check_scale(amount, f"{member} record {line}")
            key = (rm.parse_period(row[i_month]), *[intern(row[c].strip()) for c in cols])
            add_row(cells, key, amount, line, row[i_dgn].strip(), row[i_orn].strip())
    return cells, read, len(stats.joined)


def cell_tuples(file_id: int, ret: int, cells: dict[tuple, Cell], first_cell_id: int) -> Iterator[tuple]:
    """Rows of raw.forecast_return_cell in a fixed order (the key), with ids from `first_cell_id`."""
    for n, key in enumerate(sorted(cells), start=first_cell_id):
        c = cells[key]
        (period, status, typ, dgc, src, org, ec, cb0, cb1, eb) = key
        yield (
            file_id,
            n,
            ret,
            period,
            status,
            typ,
            dgc,
            c.department_group_name,
            src,
            org,
            c.organisation_name,
            ec,
            cb0,
            cb1,
            eb,
            c.amount,
            c.rows,
            c.first_line,
            c.last_line,
        )


def expected_rows(repo_root: Path) -> list[tuple]:
    out = []
    with open(repo_root / INDEPENDENT_CSV, encoding="utf-8", newline="") as fh:
        for r in csv.DictReader(fh):
            out.append(
                (
                    r["family"],
                    r["financial_year"],
                    int(r["return_no"]),
                    int(r["period"]),
                    int(r["data_rows"]),
                    r["amount_sum"],
                )
            )
    return out


def _manifest(repo_root: Path) -> tuple[list[tuple[Row, Path]], list[tuple[Row, Path]]]:
    extracts = [
        (r, p)
        for r, p in manifest_files(repo_root, ("oscar_annual_extract",))
        if r.filename.startswith("2022_OSCAR_Extract_")
        and any(r.filename.endswith(f"{y.replace('-', '_')}.zip") for y in EXTRACT_YEARS)
    ]
    mfo = [(r, p) for r, p in manifest_files(repo_root, ("oscar_mfo",)) if r.filename.endswith(".zip")]
    return extracts, mfo


def run_forecast_returns(ctx: StageContext) -> dict[str, int]:
    db, repo_root, log = ctx.db, ctx.repo_root, ctx.log
    for t in ("raw.forecast_return_cell", "raw.forecast_return_file", "raw.forecast_return_expected"):
        db.execute(f"TRUNCATE TABLE {t}")
    extracts, mfo = _manifest(repo_root)
    if len(extracts) != len(EXTRACT_YEARS) or len(mfo) != 2:
        raise FileNotFoundError(
            f"expected {len(EXTRACT_YEARS)} annual extracts and 2 MFO zips in the manifest, "
            f"found {len(extracts)} and {len(mfo)}"
        )
    for _row, path in (*extracts, *mfo):
        if not path.is_file():
            raise FileNotFoundError(f"{path.name} is not under the data directory ({path.parent})")

    file_rows: list[tuple] = []
    counts = {"raw.forecast_return_cell": 0, "raw.forecast_return_file": 0}
    file_id = 0
    cell_id = 0

    def land(file_row: tuple, ret: int, cells: dict[tuple, Cell]) -> None:
        nonlocal cell_id
        fid = file_row[0]
        n = db.insert_many("raw.forecast_return_cell", CELL_COLUMNS, cell_tuples(fid, ret, cells, cell_id + 1))
        cell_id += n
        counts["raw.forecast_return_cell"] += n
        file_rows.append(file_row)

    for row, path in extracts:
        t0 = time.perf_counter()
        member = rx.member_name(path)
        year = row.filename.removeprefix("2022_OSCAR_Extract_").removesuffix(".zip").replace("_", "-")
        by_return, rows_per_return, read = extract_cells(path, member)
        sha = file_sha256(path)
        for ret in sorted(by_return):
            file_id += 1
            cells = by_return[ret]
            # one raw.forecast_return_file row per (member, return): the member is shared by 14 returns
            land(
                (
                    file_id,
                    "extract",
                    row.source_id,
                    row.release,
                    row.filename,
                    member,
                    year,
                    ret,
                    row.sha256,
                    sha,
                    rows_per_return[ret],
                    0,
                    len(cells),
                ),
                ret,
                cells,
            )
        log(
            f"  forecast_returns {row.filename}: {read:,} rows read, {sum(rows_per_return.values()):,} in returns, "
            f"{sum(len(c) for c in by_return.values()):,} cells, {time.perf_counter() - t0:.0f} s"
        )
    for row, path in mfo:
        t0 = time.perf_counter()
        sha = file_sha256(path)
        n_cells = n_rows = 0
        for ret, year, member in rm.returns(path):
            cells, read, repaired = mfo_cells(path, member)
            file_id += 1
            land(
                (
                    file_id,
                    "mfo",
                    row.source_id,
                    row.release,
                    row.filename,
                    member,
                    year,
                    ret,
                    row.sha256,
                    sha,
                    read,
                    repaired,
                    len(cells),
                ),
                ret,
                cells,
            )
            n_cells += len(cells)
            n_rows += read
        log(
            f"  forecast_returns {row.filename}: {n_rows:,} rows read, {n_cells:,} cells, "
            f"{time.perf_counter() - t0:.0f} s"
        )
    counts["raw.forecast_return_file"] = db.insert_many("raw.forecast_return_file", FILE_COLUMNS, file_rows)
    expected = expected_rows(repo_root)
    counts["raw.forecast_return_expected"] = db.insert_many("raw.forecast_return_expected", EXPECTED_COLUMNS, expected)
    return counts


STAGE = Stage(
    name="forecast_returns",
    scope="full",
    run=run_forecast_returns,
    description="monthly forecast returns R0-R13, FY2017-18 to FY2022-23, into raw.forecast_return_cell (minutes)",
    order=300,
)
