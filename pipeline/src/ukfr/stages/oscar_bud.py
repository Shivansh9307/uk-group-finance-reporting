"""Load stage for the OSCAR annual restated ("BUD") workbooks (scope full: the files are not in git).

Reads the 15 workbooks of the three annual vintages (2023-11, 2024-11, 2025-11) through
`ukfr.readers.oscar_bud` and lands them, untyped, in:

- `raw.oscar_bud`          one row per data row: the 90 text columns of the sheet, the amount as read
                           (`amount_text`) and as an exact decimal (`amount`), lineage columns
- `quarantine.oscar_bud`   rows the load rejects, with a reason code and the row as text
- `raw.oscar_bud_file`     one row per file in the manifest: the 15 workbooks (loaded) and the
                           "Understanding OSCAR" guidance files (recorded as skipped)
- `raw.oscar_bud_control_expected`        `data/audit/bud_file_control_totals.csv`
- `raw.oscar_bud_independent_expected`    `data/audit/bud_independent_control.csv`

Everything else (typing, Closed rows, the maps, the fact, every comparison) is T-SQL under `sql/`.
"""

from __future__ import annotations

import csv
import json
from collections.abc import Iterator
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path

from ..config import FILES_CSV
from ..manifest import read_rows
from ..readers.oscar_bud import BUD_COLUMNS, BudFile, BudRow, BudStats, read_bud
from . import Stage, StageContext
from .oscar_inyear import file_sha256

CONTROL_CSV = Path("data") / "audit" / "bud_file_control_totals.csv"
INDEPENDENT_CSV = Path("data") / "audit" / "bud_independent_control.csv"

SOURCE_ID = "oscar_annual_bud"
AMOUNT_SCALE = 10  # raw.oscar_bud.amount is DECIMAL(38,10)
AMOUNT_DIGITS = 28  # integer digits that fit

TEXT_SOURCE_COLUMNS = tuple(c for c in BUD_COLUMNS if c != "AMOUNT")
RAW_COLUMNS = (
    "file_id",
    "source_row",
    "vintage",
    *(c.lower() for c in TEXT_SOURCE_COLUMNS),
    "amount_text",
    "amount",
)
QUARANTINE_COLUMNS = ("file_id", "source_row", "vintage", "reason_code", "reason_detail", "amount_text", "row_json")
FILE_COLUMNS = (
    "file_id",
    "vintage",
    "filename",
    "path",
    "file_kind",
    "load_status",
    "skip_reason",
    "sha256_manifest",
    "sha256_file",
    "financial_year",
    "sheet",
    "other_sheets",
    "total_rows",
    "blank_rows",
    "data_rows",
    "amount_forms",
)
EXPECTED_COLUMNS = (
    "vintage",
    "filename",
    "sha256",
    "financial_year",
    "total_rows",
    "blank_rows",
    "data_rows",
    "closed_rows",
    "closed_rows_with_identical_twin",
    "amount_sum_all_rows",
    "amount_sum_excluding_closed",
    "amount_closed",
    "amount_del",
    "amount_ame",
    "amount_non_budget",
    "amount_other_control_budget",
)
INDEPENDENT_COLUMNS = (
    "vintage",
    "filename",
    "sha256",
    "financial_year",
    "total_rows",
    "blank_rows",
    "data_rows",
    "closed_rows",
    "amount_sum_all_rows",
    "amount_sum_excluding_closed",
    "amount_closed",
)
INDEPENDENT_DECIMALS = ("amount_sum_all_rows", "amount_sum_excluding_closed", "amount_closed")
INDEPENDENT_INTS = ("total_rows", "blank_rows", "data_rows", "closed_rows")
EXPECTED_DECIMALS = (
    "amount_sum_all_rows",
    "amount_sum_excluding_closed",
    "amount_closed",
    "amount_del",
    "amount_ame",
    "amount_non_budget",
    "amount_other_control_budget",
)
EXPECTED_INTS = (
    "total_rows",
    "blank_rows",
    "data_rows",
    "closed_rows",
    "closed_rows_with_identical_twin",
)

REASONS = ("amount_blank", "amount_scale", "amount_range")


@dataclass
class BudResult:
    file_id: int
    f: BudFile
    stats: BudStats
    sha256_file: str
    financial_year: str = ""
    loaded: int = 0
    quarantined: int = 0


def classify(row: BudRow) -> tuple[str, str] | None:
    """(reason code, detail) if the load must reject this row, else None."""
    a = row.amount
    if a is None:
        return "amount_blank", "amount is empty"
    exponent = a.as_tuple().exponent
    if isinstance(exponent, int) and -exponent > AMOUNT_SCALE:
        return "amount_scale", f"amount {row['AMOUNT']!r} has more than {AMOUNT_SCALE} decimal places"
    if abs(int(a)) >= 10**AMOUNT_DIGITS:
        return "amount_range", f"amount {row['AMOUNT']!r} is too large"
    return None


def raw_tuple(file_id: int, row: BudRow) -> tuple:
    assert row.amount is not None
    return (file_id, row.line, row.vintage, *(row[c] for c in TEXT_SOURCE_COLUMNS), row["AMOUNT"], row.amount)


def quarantine_tuple(file_id: int, row: BudRow, reason: str, detail: str) -> tuple:
    return (file_id, row.line, row.vintage, reason, detail, row["AMOUNT"], json.dumps(row.values, sort_keys=True))


def _load_file(db, file_id: int, f: BudFile, repo_root: Path, log) -> BudResult:
    stats = BudStats()
    result = BudResult(file_id, f, stats, file_sha256(f.resolve(repo_root)))
    rejects: list[tuple] = []
    years: set[str] = set()

    def good() -> Iterator[tuple]:
        for row in read_bud(f, repo_root, stats):
            years.add(row.financial_year)
            verdict = classify(row)
            if verdict is None:
                result.loaded += 1
                yield raw_tuple(file_id, row)
            else:
                result.quarantined += 1
                rejects.append(quarantine_tuple(file_id, row, *verdict))

    db.insert_many("raw.oscar_bud", RAW_COLUMNS, good())
    if rejects:
        db.insert_many("quarantine.oscar_bud", QUARANTINE_COLUMNS, rejects)
    if len(years) != 1:
        raise ValueError(f"{f.filename}: expected one financial year, found {sorted(years)}")
    result.financial_year = next(iter(years))
    log(
        f"  oscar_bud {f.vintage} {f.filename}: read {stats.data_rows}, loaded {result.loaded}, "
        f"quarantined {result.quarantined}"
    )
    return result


def _manifest_bud_rows(repo_root: Path):
    return [r for r in read_rows(repo_root / FILES_CSV) if r.source_id == SOURCE_ID and r.fetched == "yes"]


def _file_rows(repo_root: Path, results: list[BudResult]) -> list[tuple]:
    """One row per manifest file of the source: the loaded workbooks first, then the skipped guidance."""
    by_name = {(r.f.vintage, r.f.filename): r for r in results}
    rows: list[tuple] = []
    next_id = len(results) + 1
    for m in sorted(_manifest_bud_rows(repo_root), key=lambda r: (r.release, r.filename)):
        res = by_name.get((m.release, m.filename))
        if res is not None:
            s = res.stats
            rows.append(
                (
                    res.file_id,
                    m.release,
                    m.filename,
                    m.path,
                    "data",
                    "loaded",
                    "",
                    m.sha256,
                    res.sha256_file,
                    res.financial_year,
                    s.sheet,
                    " ".join(s.other_sheets),
                    s.total_rows,
                    s.blank_rows,
                    s.data_rows,
                    " ".join(f"{k}:{v}" for k, v in sorted(s.amount_forms.items())),
                )
            )
        else:
            sha = ""
            path = BudFile(m.release, m.filename, m.path, m.sha256).resolve(repo_root)
            if path.is_file():
                sha = file_sha256(path)
            rows.append(
                (
                    next_id,
                    m.release,
                    m.filename,
                    m.path,
                    "guidance",
                    "skipped",
                    "Understanding OSCAR guidance document: describes the release, holds no data rows",
                    m.sha256,
                    sha,
                    "",
                    "",
                    "",
                    0,
                    0,
                    0,
                    "",
                )
            )
            next_id += 1
    return sorted(rows, key=lambda r: r[0])


def read_csv(repo_root: Path, rel: Path) -> list[dict[str, str]]:
    with open(repo_root / rel, encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def expected_tuple(r: dict[str, str]) -> tuple:
    return tuple(
        int(r[c]) if c in EXPECTED_INTS else Decimal(r[c]) if c in EXPECTED_DECIMALS else r[c] for c in EXPECTED_COLUMNS
    )


def independent_tuple(r: dict[str, str]) -> tuple:
    return tuple(
        int(r[c]) if c in INDEPENDENT_INTS else Decimal(r[c]) if c in INDEPENDENT_DECIMALS else r[c]
        for c in INDEPENDENT_COLUMNS
    )


def load_bud(db, repo_root: Path, files: list[BudFile] | None = None, log=print) -> dict[str, int]:
    from ..readers.oscar_bud import list_bud_files

    files = files if files is not None else list_bud_files(repo_root)
    if not files:
        raise ValueError("no BUD workbooks found in the manifest (is UKFR_DATA_DIR set and the data fetched?)")
    for t in (
        "raw.oscar_bud",
        "quarantine.oscar_bud",
        "raw.oscar_bud_file",
        "raw.oscar_bud_control_expected",
        "raw.oscar_bud_independent_expected",
    ):
        db.execute(f"TRUNCATE TABLE {t}")
    results = [_load_file(db, i, f, repo_root, log) for i, f in enumerate(files, start=1)]
    file_rows = _file_rows(repo_root, results)
    db.insert_many("raw.oscar_bud_file", FILE_COLUMNS, file_rows)
    db.insert_many(
        "raw.oscar_bud_control_expected",
        EXPECTED_COLUMNS,
        [expected_tuple(r) for r in read_csv(repo_root, CONTROL_CSV)],
    )
    independent = read_csv(repo_root, INDEPENDENT_CSV)
    db.insert_many(
        "raw.oscar_bud_independent_expected", INDEPENDENT_COLUMNS, [independent_tuple(r) for r in independent]
    )
    return {
        "files_loaded": len(results),
        "files_skipped": len(file_rows) - len(results),
        "rows_read": sum(r.stats.data_rows for r in results),
        "rows_loaded": sum(r.loaded for r in results),
        "rows_quarantined": sum(r.quarantined for r in results),
    }


def run(ctx: StageContext) -> dict[str, int]:
    return load_bud(ctx.db, ctx.repo_root, log=ctx.log)


STAGE = Stage(
    name="oscar_bud",
    scope="full",
    run=run,
    description="OSCAR annual restated (BUD) workbooks into raw.oscar_bud, with quarantine and file records",
)
