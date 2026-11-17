"""Load stage for the OSCAR II in-year releases (committed files only).

Reads every in-year data file through `ukfr.readers.oscar_inyear` and lands it, untyped, in:

- `raw.oscar_inyear`          one row per data row of each release's primary file
- `quarantine.oscar_inyear`   rows the load rejects, with a reason code and the text as read
- `raw.oscar_inyear_file`     one row per data file: sha256, rows read, load status, twin proof
- `raw.oscar_inyear_control_expected`   `data/audit/inyear_file_control_totals.csv`, as expected values

Types, zero rows, periods and every comparison with the expected values are T-SQL under `sql/`.

Amount. The exact value is stored as two columns whose sum is the source amount with no rounding:
`amount_whole` (the integer part, toward zero) and `amount_frac` (the rest, `DECIMAL(38,31)`, same
sign). Some 2026 amounts carry 31 decimal places, more than any single `DECIMAL` can hold next to
an integer part of ten digits.
"""

from __future__ import annotations

import csv
import hashlib
import re
from collections.abc import Iterator
from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path

from ..config import FILES_CSV
from ..manifest import read_rows
from ..readers.oscar_inyear import InyearFile, InyearRow, ReadStats, list_inyear_files, read_inyear
from . import Stage, StageContext

CONTROL_CSV = Path("data") / "audit" / "inyear_file_control_totals.csv"

FRAC_SCALE = 31
WHOLE_LIMIT = 10**18  # |integer part| must stay below this (BIGINT holds 9.2e18)
PERIOD0_RE = re.compile(r"^Period 0 - \d{2}-\d{2}$")

TEXT_COLUMNS = (
    "organisation_code",
    "organisation_name",
    "control_budget_code",
    "control_budget_detail_code",
    "department_name",
    "sub_segment_code",
    "sub_segment_name",
    "economic_category_code",
    "economic_category_name",
    "economic_budget_code",
    "pesa_economic_group_code",
    "pesa_economic_group_name",
    "version",
    "year",
    "quarter",
    "month",
    "amount_text",
)
RAW_COLUMNS = ("file_id", "source_row", "release", *TEXT_COLUMNS, "amount_whole", "amount_frac")
QUARANTINE_COLUMNS = ("file_id", "source_row", "release", "reason_code", "reason_detail", *TEXT_COLUMNS)
FILE_COLUMNS = (
    "file_id",
    "release",
    "filename",
    "member",
    "container",
    "primary_for_release",
    "first_published",
    "sha256_manifest",
    "sha256_file",
    "header_variant",
    "sheet",
    "total_rows",
    "blank_rows",
    "data_rows",
    "load_status",
    "duplicate_of_file_id",
    "duplicate_identical",
    "content_digest",
)
EXPECTED_COLUMNS = (
    "release",
    "filename",
    "primary_for_release",
    "sha256",
    "total_rows",
    "blank_rows",
    "data_rows",
    "zero_rows",
    "amount_sum",
    "amount_sum_rounded_4dp",
)

REASONS = ("amount_unparseable", "amount_blank", "amount_scale", "amount_range", "month_unrecognised")


@dataclass(frozen=True)
class Tables:
    """Target tables. The defaults are the real ones; tests point them at scratch copies."""

    raw: str = "raw.oscar_inyear"
    quarantine: str = "quarantine.oscar_inyear"
    file: str = "raw.oscar_inyear_file"
    expected: str = "raw.oscar_inyear_control_expected"


@dataclass
class FileResult:
    file_id: int
    f: InyearFile
    stats: ReadStats
    sha256_file: str
    loaded: int = 0
    quarantined: int = 0
    digest: str = ""
    row_count: int = 0
    reasons: dict[str, int] = field(default_factory=dict)


# -- pure helpers (no database) -----------------------------------------------------------------


def plain(value: Decimal) -> str:
    """Exact, normalised plain-text form of a decimal: no exponent, no trailing zeros, no '-0'."""
    s = format(value, "f")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s


def split_amount(amount: Decimal) -> tuple[int, Decimal]:
    """(whole, frac) with whole + frac == amount exactly, both with the sign of the amount."""
    s = format(amount, "f")
    negative = s.startswith("-")
    whole_s, _, frac_s = s.lstrip("-").partition(".")
    whole = int(whole_s or "0")
    frac = Decimal("0." + frac_s) if frac_s else Decimal(0)
    return (-whole, -frac) if negative else (whole, frac)


def classify(row: InyearRow) -> tuple[str, str] | None:
    """(reason code, detail) if the load must reject this row, else None."""
    if row.amount is None:
        if row.amount_form.endswith("unparseable"):
            return "amount_unparseable", f"amount {row.amount_text!r} is not a number"
        return "amount_blank", "amount is empty"
    exponent = row.amount.as_tuple().exponent
    if isinstance(exponent, int) and -exponent > FRAC_SCALE:
        return "amount_scale", f"amount {row.amount_text!r} has more than {FRAC_SCALE} decimal places"
    if abs(int(row.amount)) >= WHOLE_LIMIT:
        return "amount_range", f"amount {row.amount_text!r} is too large"
    if row.period == 0 and not PERIOD0_RE.match(row.month):
        return "month_unrecognised", f"month {row.month!r} is neither a calendar month nor 'Period 0 - yy-yy'"
    return None


def raw_tuple(file_id: int, row: InyearRow) -> tuple:
    assert row.amount is not None
    whole, frac = split_amount(row.amount)
    return (file_id, row.line, row.release, *(getattr(row, c) for c in TEXT_COLUMNS), whole, frac)


def quarantine_tuple(file_id: int, row: InyearRow, reason: str, detail: str) -> tuple:
    return (file_id, row.line, row.release, reason, detail, *(getattr(row, c) for c in TEXT_COLUMNS))


def row_digest(row: InyearRow) -> str:
    """Identity of a row for comparing two files: every canonical column and the exact amount."""
    amount = plain(row.amount) if row.amount is not None else f"<{row.amount_text}>"
    parts = [getattr(row, c) for c in TEXT_COLUMNS[:-1]] + [amount]
    return hashlib.sha256("\x1f".join(parts).encode("utf-8")).hexdigest()


def content_digest(digests: list[str]) -> str:
    """Order-independent digest of a file's rows (the same multiset gives the same value)."""
    return hashlib.sha256("\n".join(sorted(digests)).encode("ascii")).hexdigest()


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def read_expected(repo_root: Path) -> list[dict[str, str]]:
    with open(repo_root / CONTROL_CSV, encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def expected_tuple(r: dict[str, str]) -> tuple:
    return (
        r["release"],
        r["filename"],
        r["primary_for_release"],
        r["sha256"],
        int(r["total_rows"]),
        int(r["blank_rows"]),
        int(r["data_rows"]),
        int(r["zero_rows"]),
        plain(Decimal(r["amount_sum"])),
        plain(Decimal(r["amount_sum_rounded_4dp"])),
    )


def choose_primaries(files: list[InyearFile], expected: list[dict[str, str]]) -> dict[tuple[str, str], bool]:
    """(release, filename) -> is the file the one to load. Taken from the expected-values CSV, and
    checked: every manifest file is in the CSV with the same sha256, one primary per release."""
    by_key = {(r["release"], r["filename"]): r for r in expected}
    flags: dict[tuple[str, str], bool] = {}
    for f in files:
        r = by_key.get((f.release, f.filename))
        if r is None:
            raise ValueError(f"{f.release}/{f.filename} is in the manifest but not in {CONTROL_CSV.as_posix()}")
        if r["sha256"] != f.sha256:
            raise ValueError(f"{f.release}/{f.filename}: manifest sha256 differs from {CONTROL_CSV.as_posix()}")
        flags[(f.release, f.filename)] = r["primary_for_release"] == "Y"
    extra = set(by_key) - {(f.release, f.filename) for f in files}
    if extra:
        raise ValueError(f"{CONTROL_CSV.as_posix()} lists files the manifest does not: {sorted(extra)}")
    per_release: dict[str, int] = {}
    for (release, _), primary in flags.items():
        per_release[release] = per_release.get(release, 0) + (1 if primary else 0)
    bad = {r: n for r, n in per_release.items() if n != 1}
    if bad:
        raise ValueError(f"each release needs exactly one primary file; found {bad}")
    return flags


# -- loading --------------------------------------------------------------------------------------


def load_rows(
    db,
    file_id: int,
    f: InyearFile,
    rows: Iterator[InyearRow],
    stats: ReadStats,
    tables: Tables,
    *,
    keep_digest: bool,
) -> FileResult:
    """Classify the rows of one file, bulk load the good ones, then the rejects."""
    result = FileResult(file_id, f, stats, "")
    rejects: list[tuple] = []
    digests: list[str] = []

    def good() -> Iterator[tuple]:
        for row in rows:
            result.row_count += 1
            if keep_digest:
                digests.append(row_digest(row))
            verdict = classify(row)
            if verdict is None:
                result.loaded += 1
                yield raw_tuple(file_id, row)
            else:
                reason, detail = verdict
                result.quarantined += 1
                result.reasons[reason] = result.reasons.get(reason, 0) + 1
                rejects.append(quarantine_tuple(file_id, row, reason, detail))

    db.insert_many(tables.raw, RAW_COLUMNS, good())
    if rejects:
        db.insert_many(tables.quarantine, QUARANTINE_COLUMNS, rejects)
    result.digest = content_digest(digests) if keep_digest else ""
    return result


def _first_published(repo_root: Path) -> dict[tuple[str, str], str]:
    out = {}
    for r in read_rows(repo_root / FILES_CSV):
        if r.source_id == "oscar_inyear":
            out[(r.release, r.filename)] = r.first_published
    return out


def load_inyear(
    db, repo_root: Path, tables: Tables | None = None, log=print, files: list[InyearFile] | None = None
) -> dict[str, int]:
    tables = tables or Tables()
    files = files if files is not None else list_inyear_files(repo_root)
    expected = read_expected(repo_root)
    primaries = choose_primaries(files, expected)
    published = _first_published(repo_root)
    multi = {r for r in {f.release for f in files} if sum(1 for f in files if f.release == r) > 1}

    for t in (tables.raw, tables.quarantine, tables.file, tables.expected):
        db.execute(f"TRUNCATE TABLE {t}")

    results: list[FileResult] = []
    for file_id, f in enumerate(files, start=1):
        primary = primaries[(f.release, f.filename)]
        stats = ReadStats()
        sha = file_sha256(f.resolve(repo_root))
        rows = read_inyear(f, repo_root, stats, lenient=True)
        if primary:
            res = load_rows(db, file_id, f, rows, stats, tables, keep_digest=f.release in multi)
        else:
            res = FileResult(file_id, f, stats, sha)
            digests = []
            for row in rows:
                res.row_count += 1
                digests.append(row_digest(row))
            res.digest = content_digest(digests)
        res.sha256_file = sha
        results.append(res)
        log(
            f"  oscar_inyear {f.release} {f.filename}: read {stats.data_rows}, "
            + (f"loaded {res.loaded}, quarantined {res.quarantined}" if primary else "not loaded (duplicate)")
        )

    primary_of = {r.f.release: r for r in results if primaries[(r.f.release, r.f.filename)]}
    file_rows = []
    for r in results:
        f = r.f
        primary = primaries[(f.release, f.filename)]
        dup_of = dup_same = None
        if not primary:
            twin = primary_of[f.release]
            dup_of = twin.file_id
            dup_same = int(twin.digest == r.digest and twin.row_count == r.row_count and r.row_count > 0)
        file_rows.append(
            (
                r.file_id,
                f.release,
                f.filename,
                f.member,
                f.container,
                "Y" if primary else "N",
                published[(f.release, f.filename)],
                f.sha256,
                r.sha256_file,
                r.stats.header_variant,
                r.stats.sheet,
                r.stats.total_rows,
                r.stats.blank_rows,
                r.stats.data_rows,
                "loaded" if primary else "duplicate_of_primary",
                dup_of,
                dup_same,
                r.digest or None,
            )
        )
    db.insert_many(tables.file, FILE_COLUMNS, file_rows)
    db.insert_many(tables.expected, EXPECTED_COLUMNS, [expected_tuple(e) for e in expected])

    return {
        "files": len(results),
        "files_loaded": len(primary_of),
        "rows_read": sum(r.stats.data_rows for r in results if primaries[(r.f.release, r.f.filename)]),
        "rows_loaded": sum(r.loaded for r in results),
        "rows_quarantined": sum(r.quarantined for r in results),
    }


def run(ctx: StageContext) -> dict[str, int]:
    return load_inyear(ctx.db, ctx.repo_root, log=ctx.log)


STAGE = Stage(
    name="oscar_inyear",
    scope="committed",
    run=run,
    description="OSCAR II in-year releases into raw.oscar_inyear, with quarantine and file records",
)
