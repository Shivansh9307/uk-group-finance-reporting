"""Load stage for the NHS trust accounts consolidation (TAC) files (scope full: the files are not in git).

Reads the 12 data workbooks (six years, trusts and foundation trusts) and the six illustrative forms
through `ukfr.readers.tac` and lands them, untyped, in:

- `raw.tac_file`             one row per workbook, with its hash and the row counts the reader saw
- `raw.tac_worksheet`        rows per worksheet of `All data`, loaded or not (the three statements are loaded)
- `raw.tac_value`            one row per statement value: provider name, worksheet, table, main code,
                             form row, sub code, the value as read and as an exact decimal
- `raw.tac_provider_list`    the `List of providers` sheet (the ODS code is only here)
- `raw.tac_intro`            the `Intro` text of each data file
- `raw.tac_template_line`    the statement sheets of each illustrative form (line text, sign, sub code)
- `raw.tac_independent_expected`   `data/audit/tac_independent_control.csv`
- `quarantine.tac_value`     rows the load rejects, with a reason

Everything else (providers, lines, the fact, every comparison) is T-SQL under `sql/`.
"""

from __future__ import annotations

import csv
import json
from collections.abc import Iterator
from decimal import Decimal
from pathlib import Path

from ..readers.tac import (
    DATA_COLUMNS,
    TacFile,
    TacRow,
    TacStats,
    list_tac_files,
    read_data,
    read_intro,
    read_providers,
    read_template,
    worksheet_code,
)
from ..readers.tac import STATEMENTS as STATEMENT_CODES
from . import Stage, StageContext
from .oscar_inyear import file_sha256

INDEPENDENT_CSV = Path("data") / "audit" / "tac_independent_control.csv"

VALUE_SCALE = 10  # raw.tac_value.value is DECIMAL(38,10)
VALUE_DIGITS = 28  # integer digits that fit

FILE_COLUMNS = (
    "file_id",
    "release",
    "filename",
    "path",
    "file_kind",
    "provider_type",
    "sha256_manifest",
    "sha256_file",
    "sheets",
    "data_header",
    "total_rows",
    "blank_rows",
    "data_rows",
    "statement_rows",
)
VALUE_COLUMNS = ("file_id", "source_row", *DATA_COLUMNS[:-1], "value_text", "value")
QUARANTINE_COLUMNS = ("file_id", "source_row", "reason_code", "reason_detail", "value_text", "row_json")
PROVIDER_COLUMNS = (
    "file_id",
    "source_row",
    "provider_name",
    "nhs_code",
    "authorisation_date",
    "region",
    "sector",
    "comments",
)
TEMPLATE_COLUMNS = (
    "file_id",
    "worksheet_name",
    "source_row",
    "table_id",
    "label",
    "expected_sign",
    "sub_code",
    "main_code_cy",
    "main_code_py",
)
EXPECTED_COLUMNS = ("release", "filename", "worksheet_name", "data_rows", "value_sum")


def classify(row: TacRow) -> tuple[str, str] | None:
    """Why a row cannot be loaded, or None. Nothing is dropped silently."""
    a = row.amount
    if a is None:
        return "value_blank", "the value is empty"
    exponent = a.as_tuple().exponent
    if isinstance(exponent, int) and -exponent > VALUE_SCALE:
        return "value_scale", f"value {row.values[-1]!r} has more than {VALUE_SCALE} decimal places"
    if abs(int(a)) >= 10**VALUE_DIGITS:
        return "value_range", f"value {row.values[-1]!r} is too large"
    return None


def read_csv(repo_root: Path, rel: Path) -> list[dict[str, str]]:
    with open(repo_root / rel, encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def load_tac(db, repo_root: Path, log=print) -> dict[str, int]:
    files = list_tac_files(repo_root)
    data_files = [f for f in files if f.kind == "data"]
    template_files = [f for f in files if f.kind == "template"]
    if not data_files:
        raise ValueError("no TAC data file in the manifest (is UKFR_DATA_DIR set and the data fetched?)")
    for t in (
        "raw.tac_value",
        "quarantine.tac_value",
        "raw.tac_worksheet",
        "raw.tac_provider_list",
        "raw.tac_intro",
        "raw.tac_template_line",
        "raw.tac_file",
        "raw.tac_independent_expected",
    ):
        db.execute(f"TRUNCATE TABLE {t}")

    file_rows: list[tuple] = []
    worksheet_rows: list[tuple] = []
    totals = {"read": 0, "loaded": 0, "quarantined": 0, "providers": 0, "template_rows": 0}
    for file_id, f in enumerate(files, start=1):
        path = f.resolve(repo_root)
        sha = file_sha256(path) if path.is_file() else ""
        stats = TacStats()
        if f.kind == "template":
            sheets = _sheet_list(f, repo_root)
            rows = read_template(f, repo_root)
            db.insert_many(
                "raw.tac_template_line",
                TEMPLATE_COLUMNS,
                [
                    (
                        file_id,
                        r.worksheet,
                        r.line,
                        r.table_id,
                        r.label,
                        r.expected_sign,
                        r.sub_code,
                        r.main_cy,
                        r.main_py,
                    )
                    for r in rows
                ],
            )
            file_rows.append(
                (file_id, f.release, f.filename, f.path, "template", "", f.sha256, sha, sheets, "", 0, 0, 0, 0)
            )
            totals["template_rows"] += len(rows)
            log(f"  tac {f.filename}: {len(rows)} template rows")
            continue

        rejects: list[tuple] = []
        counts = {"loaded": 0}

        def good(
            f: TacFile = f,
            file_id: int = file_id,
            stats: TacStats = stats,
            rejects: list = rejects,
            counts: dict = counts,
        ) -> Iterator[tuple]:
            for row in read_data(f, repo_root, stats):
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
                            json.dumps(dict(zip(DATA_COLUMNS, row.values, strict=True))),
                        )
                    )

        db.insert_many("raw.tac_value", VALUE_COLUMNS, good())
        if rejects:
            db.insert_many("quarantine.tac_value", QUARANTINE_COLUMNS, rejects)
        providers = read_providers(f, repo_root)
        db.insert_many(
            "raw.tac_provider_list",
            PROVIDER_COLUMNS,
            [(file_id, p.line, *p.values) for p in providers],
        )
        intro = read_intro(f, repo_root)
        db.insert_many("raw.tac_intro", ("file_id", "source_row", "intro_text"), [(file_id, n, t) for n, t in intro])
        for ws, n in sorted(stats.worksheet_rows.items()):
            worksheet_rows.append((file_id, ws, n, 1 if worksheet_code(ws) in STATEMENT_CODES else 0))
        file_rows.append(
            (file_id, f.release, f.filename, f.path, "data", f.provider_type, f.sha256, sha, " | ".join(stats.sheets),
             " | ".join(stats.header), stats.total_rows, stats.blank_rows, stats.data_rows, stats.statement_rows)
        )  # fmt: skip
        totals["read"] += stats.statement_rows
        totals["loaded"] += counts["loaded"]
        totals["quarantined"] += len(rejects)
        totals["providers"] += len(providers)
        log(
            f"  tac {f.filename}: {stats.data_rows} rows, statements {stats.statement_rows}, "
            f"loaded {counts['loaded']}, quarantined {len(rejects)}, providers listed {len(providers)}"
        )

    db.insert_many("raw.tac_file", FILE_COLUMNS, file_rows)
    db.insert_many("raw.tac_worksheet", ("file_id", "worksheet_name", "data_rows", "loaded"), worksheet_rows)
    expected = [
        (r["release"], r["filename"], r["worksheet"], int(r["data_rows"]), Decimal(r["value_sum"]))
        for r in read_csv(repo_root, INDEPENDENT_CSV)
    ]
    db.insert_many("raw.tac_independent_expected", EXPECTED_COLUMNS, expected)
    return {
        "data_files": len(data_files),
        "template_files": len(template_files),
        "statement_rows_read": totals["read"],
        "statement_rows_loaded": totals["loaded"],
        "rows_quarantined": totals["quarantined"],
        "providers_listed": totals["providers"],
        "template_rows": totals["template_rows"],
    }


def _sheet_list(f: TacFile, repo_root: Path) -> str:
    from ..readers import plans as rp

    return " | ".join(rp.sheet_names(f.resolve(repo_root)))


def run(ctx: StageContext) -> dict[str, int]:
    return load_tac(ctx.db, ctx.repo_root, log=ctx.log)


STAGE = Stage(
    name="tac",
    scope="full",
    run=run,
    description="NHS trust accounts (TAC) statements into raw.tac_value, with providers, templates and quarantine",
)
