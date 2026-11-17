"""`ukfr build`: create the database, run the pre SQL, the load stages, the post SQL, write the audit.

Order of a build:

1. connect to `master`; create the database (or drop and create it with `recreate`);
2. create the eight schemas;
3. run the `pre` SQL files (landing tables, safe to repeat);
4. run the selected load stages;
5. run the `post` SQL files (everything derived; each file rebuilds what it owns);
6. write every table in schema `audit` to a CSV under the audit directory.

Everything the build writes is deterministic: no timestamps, rows in a fixed order, amounts as exact
text. Timings go to the console only.
"""

from __future__ import annotations

import csv
import time
from dataclasses import dataclass, field
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

from . import sqlrunner
from .db import DEFAULT_DATABASE, SCHEMAS, Db, DbSettings, database_exists, quote_name, wait_for_server
from .stages import StageContext, select_stages

SQL_DIR = "sql"
DEFAULT_AUDIT_DIR = Path("evidence") / "build"


@dataclass
class BuildResult:
    timings: dict[str, float] = field(default_factory=dict)
    stage_counts: dict[str, dict[str, int]] = field(default_factory=dict)
    audit_files: list[Path] = field(default_factory=list)


def plain_text(value: object) -> str:
    """CSV text of one value: exact, with no locale or float formatting."""
    if value is None:
        return ""
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, Decimal):
        s = format(value, "f")  # exact: normalize() would round to the context precision
        if "." in s:
            s = s.rstrip("0").rstrip(".")
        return "0" if s in ("", "-0") else s
    if isinstance(value, datetime):
        return value.isoformat(sep=" ")
    if isinstance(value, date):
        return value.isoformat()
    return str(value)


def create_database(settings: DbSettings, recreate: bool, log=print) -> None:
    with Db(settings.with_database("master")) as master:
        name = settings.database
        exists = database_exists(master, name)
        if exists and recreate:
            log(f"  dropping database {name}")
            master.execute(f"ALTER DATABASE {quote_name(name)} SET SINGLE_USER WITH ROLLBACK IMMEDIATE")
            master.execute(f"DROP DATABASE {quote_name(name)}")
            exists = False
        if not exists:
            log(f"  creating database {name}")
            master.execute(f"CREATE DATABASE {quote_name(name)}")
            master.execute(f"ALTER DATABASE {quote_name(name)} SET RECOVERY SIMPLE")


def create_schemas(db: Db) -> None:
    for s in SCHEMAS:
        db.execute(f"IF SCHEMA_ID(N'{s}') IS NULL EXEC(N'CREATE SCHEMA {quote_name(s)}')")


def export_audit(db: Db, out_dir: Path) -> list[Path]:
    """Write each table in schema `audit` to `<out_dir>/<table>.csv`, sorted by primary key (then by
    the whole row), UTF-8, LF line ends. Removes CSVs there that no longer have a table."""
    out_dir.mkdir(parents=True, exist_ok=True)
    tables = [r[0] for r in db.query("SELECT name FROM sys.tables WHERE schema_id = SCHEMA_ID(N'audit') ORDER BY name")]
    written: list[Path] = []
    for table in tables:
        pk = [
            r[0]
            for r in db.query(
                "SELECT c.name FROM sys.indexes i "
                "JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id "
                "JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id "
                "WHERE i.object_id = OBJECT_ID(?) AND i.is_primary_key = 1 ORDER BY ic.key_ordinal",
                (f"audit.{table}",),
            )
        ]
        names, rows = db.columns(f"SELECT * FROM audit.{quote_name(table)}")
        keys = [names.index(c) for c in pk]
        text_rows = [[plain_text(v) for v in row] for row in rows]
        # primary key columns first (numbers compared as numbers where they parse), then the whole row
        text_rows.sort(key=lambda r: ([_sort_key(r[i]) for i in keys], r))
        path = out_dir / f"{table}.csv"
        with open(path, "w", encoding="utf-8", newline="") as fh:
            w = csv.writer(fh, lineterminator="\n")
            w.writerow(names)
            w.writerows(text_rows)
        written.append(path)
    keep = {p.name for p in written}
    for stale in out_dir.glob("*.csv"):
        if stale.name not in keep:
            stale.unlink()
    return written


def _sort_key(text: str) -> tuple[int, Decimal | str]:
    try:
        return (0, Decimal(text))
    except Exception:
        return (1, text)


def build(
    settings: DbSettings,
    repo_root: Path,
    *,
    scope: str = "committed",
    stage_names: list[str] | None = None,
    recreate: bool = False,
    skip_sql: bool = False,
    audit_dir: Path | None = None,
    wait_seconds: float = 0,
    log=print,
) -> BuildResult:
    result = BuildResult()
    stages = select_stages(scope, stage_names)
    sql_files = sqlrunner.discover(repo_root / SQL_DIR)
    pre = sqlrunner.select(sql_files, "pre", scope)
    post = sqlrunner.select(sql_files, "post", scope)

    def timed(label: str, fn):
        t = time.perf_counter()
        out = fn()
        result.timings[label] = time.perf_counter() - t
        log(f"{label}: {result.timings[label]:.1f} s")
        return out

    log(f"build scope={scope} target={settings.describe()}")
    if wait_seconds > 0:
        wait_for_server(settings, wait_seconds, log)
    timed("database", lambda: create_database(settings, recreate, log))
    with Db(settings) as db:
        create_schemas(db)
        timed("pre sql", lambda: sqlrunner.run_files(db, pre, log))
        for stage in stages:
            ctx = StageContext(repo_root, db, scope, log)
            result.stage_counts[stage.name] = timed(f"stage {stage.name}", lambda s=stage, c=ctx: s.run(c))
            log(f"  {stage.name}: {result.stage_counts[stage.name]}")
        if not skip_sql:
            timed("post sql", lambda: sqlrunner.run_files(db, post, log))
            out = audit_dir if audit_dir is not None else repo_root / DEFAULT_AUDIT_DIR
            result.audit_files = timed("audit export", lambda: export_audit(db, out))
            for p in result.audit_files:
                log(f"  wrote {p.name}")
    return result


def is_main_database(settings: DbSettings) -> bool:
    return settings.database.lower() == DEFAULT_DATABASE.lower()
