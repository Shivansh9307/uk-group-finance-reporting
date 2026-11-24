"""Load stage for the departmental workforce management information files (scope full: the files are not in git).

Reads every fetched `workforce_mi` file through `ukfr.readers.workforce` and lands it, untyped, in:

- `raw.workforce_file`      one row per file: department, month, format, header layout, row counts
- `raw.workforce_row`       one row per non-blank row of the data sheet: the identifying cells as published
- `raw.workforce_value`     one row per non-blank numeric cell: column position, the measure key the reader gave the
                            column, the header as published, the text and the exact number
- `raw.workforce_ignored_column`  the comment and note columns the reader does not read (file, position, header)
- `quarantine.workforce_value`  non-blank cells that are not numbers
- `raw.workforce_control_expected`  the count and sum of every numeric column of every file, recomputed by
                            `ukfr.controls.workforce_independent`, which does not import the reader

No decision about which organisation a row is, or which month it belongs to, is taken here: that is SQL.
"""

from __future__ import annotations

import csv
from collections.abc import Iterator
from decimal import Decimal
from pathlib import Path

from ..controls import workforce_independent
from ..readers.workforce import (
    WorkforceFile,
    WorkforceFormatError,
    WorkforceStats,
    list_workforce_files,
    read_workforce,
)
from . import Stage, StageContext
from .oscar_inyear import file_sha256

FILE_COLUMNS = (
    "file_id",
    "dept",
    "report_month",
    "release",
    "filename",
    "path",
    "format",
    "is_primary",
    "load_status",
    "skip_reason",
    "sha256_manifest",
    "sha256_file",
    "sheet",
    "template",
    "header_line",
    "header_rows",
    "total_rows",
    "blank_rows",
    "data_rows",
    "n_columns",
)
ROW_COLUMNS = (
    "file_id",
    "source_row",
    "year_text",
    "month_text",
    "organisation_name",
    "organisation_type",
    "parent_department",
)
VALUE_COLUMNS = ("file_id", "source_row", "column_index", "measure_key", "column_label", "value_text", "value")
QUARANTINE_COLUMNS = (
    "file_id",
    "source_row",
    "column_index",
    "measure_key",
    "column_label",
    "value_text",
    "reason_code",
    "reason_detail",
)
EXPECTED_COLUMNS = (
    "dept",
    "report_month",
    "filename",
    "sheet",
    "column_index",
    "data_rows",
    "numeric_cells",
    "nonnumeric_cells",
    "value_sum",
)
IGNORED_COLUMNS = ("file_id", "column_index", "column_label")
TABLES = (
    "raw.workforce_ignored_column",
    "raw.workforce_value",
    "raw.workforce_row",
    "raw.workforce_file",
    "quarantine.workforce_value",
    "raw.workforce_control_expected",
)


def choose_primary(
    files: list[WorkforceFile], named_rows: dict[tuple[str, str], int]
) -> set[tuple[str, str]]:
    """The one copy per department and month that the warehouse uses, as (release, filename).

    Where a month is published in more than one format every copy is read, but only one counts: the copy with the most
    rows that have an organisation name and a non-zero value (a spreadsheet whose formulas were saved without results
    reads as zeros); on a tie the spreadsheet before the csv (a csv export of the same
    sheet has been rounded to whole people in some departments), xlsx, xls, ods, then csv. Two files of one format
    for one month are an error (the load would double count)."""
    rank = {"xlsx": 0, "xls": 1, "ods": 2, "csv": 3}
    groups: dict[tuple[str, str], list[WorkforceFile]] = {}
    for f in files:
        groups.setdefault((f.dept, f.month), []).append(f)
    out = set()
    for key, group in groups.items():
        group.sort(key=lambda f: (-named_rows[(f.release, f.filename)], rank[f.fmt], f.filename))
        for other in group[1:]:
            if other.fmt == group[0].fmt:
                raise ValueError(f"{key}: two {other.fmt} files for one month: {group[0].filename}, {other.filename}")
        out.add((group[0].release, group[0].filename))
    return out


SKIPPED_CSV = Path("data") / "manifest" / "workforce_skipped_files.csv"


def read_skipped(repo_root: Path) -> dict[tuple[str, str], str]:
    """(release, filename) -> reason, from the hand-written list of files I could not read."""
    path = repo_root / SKIPPED_CSV
    if not path.is_file():
        return {}
    with open(path, encoding="utf-8", newline="") as fh:
        return {(r["release"], r["filename"]): r["reason"] for r in csv.DictReader(fh)}


def load_file(db, repo_root: Path, f: WorkforceFile, file_id: int, skip: str = "") -> tuple[tuple, int, int, int]:
    """Load one file; returns (its raw.workforce_file row, values loaded, values quarantined, rows with a name and a
    value).

    A file in the skip list must fail to read, and then gets a file row with load_status `skipped` and its reason
    (nothing else is loaded). A file in the list that reads fine is an error (the list would be wrong), and so is a
    file that cannot be read and is not in the list."""
    stats = WorkforceStats()
    rows: list[tuple] = []
    values: list[tuple] = []
    rejects: list[tuple] = []
    try:
        for r in read_workforce(f, repo_root, stats):
            ident = (r.year, r.month, r.organisation_name, r.organisation_type, r.parent_department)
            rows.append((file_id, r.line, *ident))
            for v in r.values:
                if v.number is None:
                    detail = "the cell is not a number"
                    rejects.append(
                        (file_id, r.line, v.column_index, v.key, v.column_label, v.text, "not_a_number", detail)
                    )
                else:
                    values.append((file_id, r.line, v.column_index, v.key, v.column_label, v.text, v.number))
    except WorkforceFormatError as exc:
        if not skip:
            hint = f"(list it in {SKIPPED_CSV.as_posix()} only if it cannot be read)"
            raise WorkforceFormatError(f"{exc} {hint}") from exc
        rows, values, rejects, stats = [], [], [], WorkforceStats()
    else:
        if skip:
            raise ValueError(f"{f.release} {f.filename} is in {SKIPPED_CSV.as_posix()} but it reads fine; remove it")
    path = f.resolve(repo_root)
    sha = file_sha256(path) if path.is_file() else ""
    db.insert_many("raw.workforce_row", ROW_COLUMNS, rows)
    if stats.ignored:
        db.insert_many(
            "raw.workforce_ignored_column", IGNORED_COLUMNS, [(file_id, i, label) for i, label in stats.ignored]
        )
    db.insert_many("raw.workforce_value", VALUE_COLUMNS, values)
    if rejects:
        db.insert_many("quarantine.workforce_value", QUARANTINE_COLUMNS, rejects)
    file_row = (
        file_id, f.dept, f.month, f.release, f.filename, f.path, f.fmt, 0,
        "skipped" if skip else "loaded", skip, f.sha256, sha,
        stats.sheet, stats.template, stats.header_line, stats.header_rows,
        stats.total_rows, stats.blank_rows, stats.data_rows, len(stats.columns),
    )  # fmt: skip
    valued = {v[1] for v in values if v[6] != 0}
    named = sum(1 for r in rows if r[1] in valued and r[4].strip())
    return file_row, len(values), len(rejects), named


def expected_rows(repo_root: Path) -> Iterator[tuple]:
    for r in workforce_independent.control_rows(repo_root):
        dept, month, filename, sheet, col, n_rows, n_num, n_bad, total = r
        yield (dept, month, filename, sheet, int(col), int(n_rows), int(n_num), int(n_bad), Decimal(total))


def run(ctx: StageContext) -> dict[str, int]:
    files = list_workforce_files(ctx.repo_root)
    if not files:
        raise ValueError("no workforce files in the manifest (is UKFR_DATA_DIR set and `ukfr fetch` run?)")
    for t in TABLES:
        ctx.db.execute(f"TRUNCATE TABLE {t}")
    file_rows: list[tuple] = []
    loaded = quarantined = 0
    skipped = read_skipped(ctx.repo_root)
    unknown = sorted(set(skipped) - {(f.release, f.filename) for f in files})
    if unknown:
        raise ValueError(f"workforce_skipped_files.csv lists files that are not in the manifest: {unknown[:5]}")
    named: dict[tuple[str, str], int] = {}
    for file_id, f in enumerate(files, start=1):
        key = (f.release, f.filename)
        row, n_loaded, n_rejected, n_named = load_file(ctx.db, ctx.repo_root, f, file_id, skipped.get(key, ""))
        file_rows.append(row)
        named[key] = n_named
        loaded += n_loaded
        quarantined += n_rejected
        if file_id % 100 == 0:
            ctx.log(f"  workforce: {file_id} of {len(files)} files")
    primary = choose_primary([f for f in files if (f.release, f.filename) not in skipped], named)
    col = {name: i for i, name in enumerate(FILE_COLUMNS)}
    file_rows = [
        (*r[: col["is_primary"]], int((r[col["release"]], r[col["filename"]]) in primary), *r[col["is_primary"] + 1 :])
        if r[col["load_status"]] == "loaded"
        else r
        for r in file_rows
    ]
    ctx.db.insert_many("raw.workforce_file", FILE_COLUMNS, file_rows)
    expected = ctx.db.insert_many("raw.workforce_control_expected", EXPECTED_COLUMNS, expected_rows(ctx.repo_root))
    ctx.log(f"  workforce: {len(files)} files, {loaded} values loaded, {quarantined} quarantined")
    return {
        "files": len(files),
        "rows": sum(r[18] for r in file_rows),
        "files_skipped": len(skipped),
        "values_loaded": loaded,
        "values_quarantined": quarantined,
        "control_rows": expected,
    }


STAGE = Stage(
    name="workforce",
    scope="full",
    run=run,
    description="Departmental workforce management information into raw.workforce_*, with an independent control",
)
