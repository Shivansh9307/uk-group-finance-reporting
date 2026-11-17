"""Load stage for the Public Spending Statistics database (scope full: the file is not in git).

Reads the `Database` sheet of `PSS_Database_<year>.xlsx` through `ukfr.readers.pss` and lands it,
untyped, in:

- `raw.pss`                  one row per data row: the nine text columns, the amount as written and as
                             an exact decimal, lineage columns
- `quarantine.pss`           rows the load rejects, with a reason code
- `raw.pss_file`             one row per PSS file in the manifest: the database (loaded) and the
                             Chapter 1 tables workbook (recorded as skipped)
- `raw.pss_control_expected`        `data/audit/pss_file_control_totals.csv`
- `raw.pss_independent_expected`    `data/audit/pss_independent_control.csv`
"""

from __future__ import annotations

import csv
import json
from collections.abc import Iterator
from decimal import Decimal
from pathlib import Path

from ..readers.pss import PSS_COLUMNS, PssFile, PssRow, PssStats, list_pss_files, read_pss
from . import Stage, StageContext
from .oscar_inyear import file_sha256

CONTROL_CSV = Path("data") / "audit" / "pss_file_control_totals.csv"
INDEPENDENT_CSV = Path("data") / "audit" / "pss_independent_control.csv"

AMOUNT_SCALE = 10
AMOUNT_DIGITS = 28

TEXT_COLUMNS = (
    "year",
    "economic_budget_code",
    "economic_ringfence_code",
    "control_budget_code",
    "control_budget_detail_code",
    "sr_group_long_name",
    "segment_code",
    "segment_long_name",
    "pesa_economic_group_long_name",
)
RAW_COLUMNS = ("file_id", "source_row", *TEXT_COLUMNS, "amount_text", "amount")
QUARANTINE_COLUMNS = ("file_id", "source_row", "reason_code", "reason_detail", "amount_text", "row_json")
FILE_COLUMNS = (
    "file_id",
    "release",
    "filename",
    "path",
    "file_kind",
    "load_status",
    "skip_reason",
    "sha256_manifest",
    "sha256_file",
    "sheets",
    "total_rows",
    "blank_rows",
    "data_rows",
)
EXPECTED_COLUMNS = ("filename", "sheet", "n_columns", "total_rows", "financial_year", "amount_total")
INDEPENDENT_COLUMNS = ("filename", "sheet", "financial_year", "data_rows", "amount_sum")


def classify(row: PssRow) -> tuple[str, str] | None:
    a = row.amount
    if a is None:
        return "amount_blank", "amount is empty"
    exponent = a.as_tuple().exponent
    if isinstance(exponent, int) and -exponent > AMOUNT_SCALE:
        return "amount_scale", f"amount {row.values[-1]!r} has more than {AMOUNT_SCALE} decimal places"
    if abs(int(a)) >= 10**AMOUNT_DIGITS:
        return "amount_range", f"amount {row.values[-1]!r} is too large"
    return None


def read_csv(repo_root: Path, rel: Path) -> list[dict[str, str]]:
    with open(repo_root / rel, encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def load_pss(db, repo_root: Path, log=print) -> dict[str, int]:
    files = list_pss_files(repo_root)
    data_files = [f for f in files if f.is_database]
    if not data_files:
        raise ValueError("no PSS database in the manifest (is UKFR_DATA_DIR set and the data fetched?)")
    for t in ("raw.pss", "quarantine.pss", "raw.pss_file", "raw.pss_control_expected", "raw.pss_independent_expected"):
        db.execute(f"TRUNCATE TABLE {t}")

    file_rows: list[tuple] = []
    loaded = quarantined = read = 0
    next_id = 1
    for f in files:
        file_id = next_id
        next_id += 1
        path = f.resolve(repo_root)
        sha = file_sha256(path) if path.is_file() else ""
        if not f.is_database:
            file_rows.append(
                (file_id, f.release, f.filename, f.path, "tables", "skipped",
                 "Chapter 1 summary tables, not the database sheet; not loaded here", f.sha256, sha, "", 0, 0, 0)
            )  # fmt: skip
            continue
        stats = PssStats()
        rejects: list[tuple] = []
        counts = {"loaded": 0}

        def good(f: PssFile = f, file_id: int = file_id, stats: PssStats = stats, rejects: list = rejects,
                 counts: dict = counts) -> Iterator[tuple]:  # fmt: skip
            for row in read_pss(f, repo_root, stats):
                verdict = classify(row)
                if verdict is None:
                    counts["loaded"] += 1
                    yield (file_id, row.line, *row.values[:-1], row.values[-1], row.amount)
                else:
                    rejects.append(
                        (
                            file_id,
                            row.line,
                            *verdict,
                            row.values[-1],
                            json.dumps(dict(zip(PSS_COLUMNS, row.values, strict=True))),
                        )
                    )

        db.insert_many("raw.pss", RAW_COLUMNS, good())
        if rejects:
            db.insert_many("quarantine.pss", QUARANTINE_COLUMNS, rejects)
        file_rows.append(
            (file_id, f.release, f.filename, f.path, "database", "loaded", "", f.sha256, sha, " ".join(stats.sheets),
             stats.total_rows, stats.blank_rows, stats.data_rows)
        )  # fmt: skip
        loaded += counts["loaded"]
        quarantined += len(rejects)
        read += stats.data_rows
        log(f"  pss {f.filename}: read {stats.data_rows}, loaded {counts['loaded']}, quarantined {len(rejects)}")

    db.insert_many("raw.pss_file", FILE_COLUMNS, file_rows)
    expected = [
        (
            r["file"],
            r["sheet"],
            int(r["columns"]),
            int(r["rows"]),
            r["fiscal_year"],
            Decimal(r["amount_total_gbp_thousand"]),
        )
        for r in read_csv(repo_root, CONTROL_CSV)
    ]
    db.insert_many("raw.pss_control_expected", EXPECTED_COLUMNS, expected)
    independent = [
        (r["filename"], r["sheet"], r["financial_year"], int(r["data_rows"]), Decimal(r["amount_sum"]))
        for r in read_csv(repo_root, INDEPENDENT_CSV)
    ]
    db.insert_many("raw.pss_independent_expected", INDEPENDENT_COLUMNS, independent)
    return {
        "files_loaded": len(data_files),
        "files_skipped": len(files) - len(data_files),
        "rows_read": read,
        "rows_loaded": loaded,
        "rows_quarantined": quarantined,
    }


def run(ctx: StageContext) -> dict[str, int]:
    return load_pss(ctx.db, ctx.repo_root, log=ctx.log)


STAGE = Stage(
    name="pss",
    scope="full",
    run=run,
    description="Public Spending Statistics database into raw.pss, with quarantine and file records",
)
