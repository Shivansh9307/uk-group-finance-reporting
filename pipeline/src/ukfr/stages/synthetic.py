"""Load stage for synthetic CSV files: every `synthetic/*.csv` is written to `synthetic.<file stem>`.

A synthetic file is invented data (a user list, for example). Unlike an authored file it lands in a table that a
`-- phase: pre` file in `sql/synthetic/` has already created with typed columns and checks, because the checks (the
reserved e-mail domain, the `synthetic` class) belong in the schema and not in a view. The loader reads the file with
the standard `csv` module (the same reader and the same file checks as the authored stage), empties the table and
writes the rows with a `_load_order` column (1.. in file order). It makes no decision about them and the file holds
no amount. A file whose table does not exist stops the build with the file's name.
"""

from __future__ import annotations

from pathlib import Path

from ..db import quote_name
from . import Stage, StageContext
from .authored import AuthoredFileError, read_authored

SYNTHETIC_DIR = "synthetic"


def list_synthetic_files(root: Path) -> list[Path]:
    """Every CSV in `<root>/synthetic`, sorted by name. A missing folder means none."""
    folder = root / SYNTHETIC_DIR
    return sorted(folder.glob("*.csv")) if folder.is_dir() else []


def load_one(ctx: StageContext, path: Path) -> int:
    header, rows = read_authored(path)
    if ctx.db.scalar("SELECT OBJECT_ID(?)", (f"synthetic.{path.stem}",)) is None:
        raise AuthoredFileError(
            f"{path.name}: there is no table synthetic.{path.stem}; add sql/synthetic/NNN_{path.stem}.sql"
        )
    table = f"synthetic.{quote_name(path.stem)}"
    ctx.db.execute(f"DELETE FROM {table};")
    if rows:
        ctx.db.insert_many(
            table,
            ["_load_order", *header],
            ([i, *fields] for i, fields in enumerate(rows, start=1)),
        )
    return len(rows)


def run(ctx: StageContext) -> dict[str, int]:
    counts: dict[str, int] = {}
    for path in list_synthetic_files(ctx.repo_root):
        counts[path.stem] = load_one(ctx, path)
        ctx.log(f"  synthetic {path.name}: {counts[path.stem]} rows")
    return counts


STAGE = Stage(
    name="synthetic",
    scope="committed",
    run=run,
    description="every synthetic/*.csv into synthetic.<file stem>, whose typed table sql/synthetic creates",
    order=55,
)
