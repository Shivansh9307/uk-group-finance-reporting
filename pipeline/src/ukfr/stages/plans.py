"""Load stages for the spending plans.

`plans` (scope committed) reads the Estimates "Departmental DEL budgets" workbooks and the PESA and
Spending Review 2025 workbooks, which are committed under `data/committed/`, with
`ukfr.readers.plans.read_tables`. Every cell of every table sheet lands in `raw.plan_estimates` or
`raw.plan_pesa` as published: the unit text, the row label with its footnote marker (and the cleaned
label), the year label, the plans/outturn label and the number. Nothing is converted to GBP thousands
here; that is T-SQL. The authored plan files (`authored/plan_name_map.csv`, `plan_source.csv`, `sr_group.csv`) are
loaded as text by the generic `authored` stage, not here.

`plans_oscar` (scope full) streams the five November 2022 annual extracts under `$UKFR_DATA_DIR` and
lands the rows whose VERSION_CODE is PLANS in `raw.plan_oscar`, plus two control csv files that are in git.
The extracts are Deflate64 zips read as streams (never written to disk); about 12 GB of text is
decompressed to keep 140 thousand rows, which is why this stage takes minutes.
"""

from __future__ import annotations

import csv
import hashlib
from collections.abc import Iterator
from pathlib import Path

from ..config import FILES_CSV, data_dir
from ..manifest import RAW_PREFIX, Row, read_rows
from ..readers import oscar_extract as rx
from ..readers import plans as rp
from . import Stage, StageContext

EXTRACT_CONTROL_CSV = Path("data") / "audit" / "extract_file_control_totals.csv"
PLAN_TOTALS_CSV = Path("docs") / "profiling" / "data" / "plan_oscar_totals.csv"

TABLE_COLUMNS = (
    "file_id",
    "source_row",
    "sheet",
    "table_title",
    "unit",
    "section",
    "row_label",
    "row_label_clean",
    "row_kind",
    "year_label",
    "status_label",
    "value_text",
    "value_published",
)
FILE_COLUMNS = (
    "file_id",
    "family",
    "source_id",
    "release",
    "edition",
    "filename",
    "sha256_manifest",
    "sha256_file",
    "first_published",
    "sheets_read",
    "rows_loaded",
)
OSCAR_COLUMNS = (
    "file_id",
    "source_row",
    "year_short_name",
    "month_short_name",
    "department_group_code",
    "department_group_name",
    "sr_group_code",
    "sr_group_name",
    "organisation_code",
    "organisation_name",
    "segment_l4_code",
    "control_budget_l0_name",
    "control_budget_l1_name",
    "economic_budget_code",
    "economic_ringfence_code",
    "economic_group_code",
    "economic_category_code",
    "usage_code",
    "status_code",
    "type_code",
    "version_code",
    "amount_text",
)
OSCAR_SOURCE_COLUMNS = (
    "YEAR_SHORT_NAME",
    "MONTH_SHORT_NAME",
    "DEPARTMENT_GROUP_CODE",
    "DEPARTMENT_GROUP_LONG_NAME",
    "SR_GROUP_CODE",
    "SR_GROUP_LONG_NAME",
    "ORGANISATION_CODE",
    "ORGANISATION_LONG_NAME",
    "SEGMENT_L4_CODE",
    "CONTROL_BUDGET_L0_LONG_NAME",
    "CONTROL_BUDGET_L1_LONG_NAME",
    "ECONOMIC_BUDGET_CODE",
    "ECONOMIC_RINGFENCE_CODE",
    "ECONOMIC_GROUP_CODE",
    "ECONOMIC_CATEGORY_CODE",
    "USAGE_CODE",
    "STATUS_CODE",
    "TYPE_CODE",
    "VERSION_CODE",
    "AMOUNT",
)
EXPECTED_COLUMNS = (
    "control",
    "fiscal_year",
    "department_group_code",
    "control_budget_detail",
    "economic_budget",
    "plans_rows",
    "plans_gbp_thousand",
)

def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def edition_of(row: Row) -> str:
    """Edition label: the manifest release, except that the two PESA 2025 files are told apart."""
    if row.source_id == "pesa" and row.release == "2025":
        return "2025-12" if "_Dec_" in row.filename else "2025-07"
    return row.release


def manifest_files(repo_root: Path, source_ids: tuple[str, ...]) -> list[tuple[Row, Path]]:
    """(manifest row, absolute path) for every fetched file of the given sources, in a fixed order."""
    out = []
    for r in read_rows(repo_root / FILES_CSV):
        if r.source_id in source_ids and r.fetched == "yes":
            path = (data_dir(repo_root) / r.path[len(RAW_PREFIX) :]) if r.path.startswith(RAW_PREFIX) else repo_root / r.path
            out.append((r, path))
    return sorted(out, key=lambda x: (x[0].source_id, edition_of(x[0]), x[0].filename))


def _value_text(v) -> str | None:
    return None if v is None else format(v, "f")


def table_rows(file_id: int, tables: list[rp.Table]) -> Iterator[tuple]:
    for t in tables:
        for r in t.rows:
            for year in t.years:
                v = r.values[year]
                yield (
                    file_id,
                    r.row + 1,
                    t.sheet,
                    t.title,
                    t.unit,
                    r.section,
                    r.raw_name,
                    r.name,
                    r.kind,
                    year,
                    t.statuses.get(year, ""),
                    _value_text(v),
                    v,
                )


def run_plans(ctx: StageContext) -> dict[str, int]:
    db, repo_root = ctx.db, ctx.repo_root
    for t in ("raw.plan_estimates", "raw.plan_pesa"):
        db.execute(f"TRUNCATE TABLE {t}")
    db.execute("DELETE FROM raw.plan_source_file WHERE family <> 'oscar_extract'")
    counts: dict[str, int] = {}
    file_rows = []
    for file_id, (row, path) in enumerate(manifest_files(repo_root, ("estimates_del", "pesa")), start=1):
        family = "estimates" if row.source_id == "estimates_del" else "pesa"
        table = f"raw.plan_{family}"
        tables = rp.read_tables(path)
        n = db.insert_many(table, TABLE_COLUMNS, table_rows(file_id, tables))
        counts[table] = counts.get(table, 0) + n
        file_rows.append(
            (
                file_id,
                family,
                row.source_id,
                row.release,
                edition_of(row),
                row.filename,
                row.sha256,
                file_sha256(path),
                row.first_published,
                len(tables),
                n,
            )
        )
        ctx.log(f"  plans {family} {edition_of(row)} {row.filename}: {len(tables)} sheets, {n} cells")
    db.insert_many("raw.plan_source_file", FILE_COLUMNS, file_rows)
    counts["raw.plan_source_file"] = len(file_rows)
    return counts


def oscar_plan_rows(file_id: int, path: Path) -> Iterator[tuple]:
    """The PLANS rows of one extract, as text, in file order."""
    with rx.open_extract(path) as (header, ix, rows):
        cols = [ix[c] for c in OSCAR_SOURCE_COLUMNS]
        i_ver = ix["VERSION_CODE"]
        n = 0
        for row in rows:
            n += 1
            if row[i_ver] != "PLANS":
                continue
            yield (file_id, n, *(row[c].strip() if c != ix["AMOUNT"] else row[c] for c in cols))


def expected_rows(repo_root: Path) -> list[tuple]:
    out = []
    with open(repo_root / EXTRACT_CONTROL_CSV, encoding="utf-8", newline="") as fh:
        for r in csv.DictReader(fh):
            out.append(("file_plans_rows", r["fiscal_year"], "", "", "", int(r["plans_rows"]), None))
    with open(repo_root / PLAN_TOTALS_CSV, encoding="utf-8", newline="") as fh:
        for r in csv.DictReader(fh):
            out.append(
                (
                    "group_totals",
                    r["fiscal_year"],
                    r["department_group_code"],
                    r["control_budget_detail"],
                    r["economic_budget"],
                    int(r["plans_rows"]),
                    r["plans_gbp_thousand"],
                )
            )
    return out


def run_plans_oscar(ctx: StageContext) -> dict[str, int]:
    db, repo_root = ctx.db, ctx.repo_root
    for t in ("raw.plan_oscar", "raw.plan_oscar_expected"):
        db.execute(f"TRUNCATE TABLE {t}")
    db.execute("DELETE FROM raw.plan_source_file WHERE family = 'oscar_extract'")
    # file ids continue after the workbooks, so raw.plan_source_file keeps one numbering
    start = (db.scalar("SELECT COALESCE(MAX(file_id), 0) FROM raw.plan_source_file") or 0) + 1
    files = manifest_files(repo_root, ("oscar_annual_extract",))
    files = [(r, p) for r, p in files if r.filename.startswith("2022_OSCAR_Extract_")]
    if len(files) != 5:
        raise FileNotFoundError(f"expected the five 2022 annual extracts in the manifest, found {len(files)}")
    total = 0
    file_rows = []
    for file_id, (row, path) in enumerate(files, start=start):
        if not path.is_file():
            raise FileNotFoundError(f"{path.name} is not under the data directory ({path.parent})")
        n = db.insert_many("raw.plan_oscar", OSCAR_COLUMNS, oscar_plan_rows(file_id, path))
        total += n
        file_rows.append(
            (
                file_id,
                "oscar_extract",
                row.source_id,
                row.release,
                row.release,
                row.filename,
                row.sha256,
                file_sha256(path),
                row.first_published,
                1,
                n,
            )
        )
        ctx.log(f"  plans_oscar {row.filename}: {n} plan rows")
    db.insert_many("raw.plan_source_file", FILE_COLUMNS, file_rows)
    expected = expected_rows(repo_root)
    db.insert_many("raw.plan_oscar_expected", EXPECTED_COLUMNS, expected)
    return {"raw.plan_oscar": total, "raw.plan_oscar_expected": len(expected)}


STAGES = [
    Stage(
        name="plans",
        scope="committed",
        run=run_plans,
        description="Estimates, PESA and SR25 plan tables into raw.plan_estimates and raw.plan_pesa",
        order=200,
    ),
    Stage(
        name="plans_oscar",
        scope="full",
        run=run_plans_oscar,
        description="PLANS rows of the OSCAR annual extracts into raw.plan_oscar (reads 12 GB of text, minutes)",
        order=210,
    ),
]
