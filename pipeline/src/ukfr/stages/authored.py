"""Load stage for authored CSV files: every `authored/*.csv` becomes `authored.<file stem>`.

An authored file is a small table I wrote by hand (an override list, a name per period, a mapping).
The loader makes no decision about it. It reads the file with the standard `csv` module and lands it,
untyped, in a table with:

- `_load_order`   1.. in file order, so a row can always be traced back to its line in the file
- one `nvarchar(max)` column per header name, in header order, holding the text exactly as written
  (an empty field is an empty string, never NULL)

Typing, defaults and every check are T-SQL under `sql/`. A new authored file therefore needs no Python
change: drop it into `authored/`, and the next build loads it. The table is dropped and created again
on every build, so it always equals the file. Each table carries an extended property `MS_Description`
that says it is authored, not source data.
"""

from __future__ import annotations

import csv
import re
from pathlib import Path

from ..db import quote_name
from . import Stage, StageContext

AUTHORED_DIR = "authored"
STEM_RE = re.compile(r"^[a-z][a-z0-9_]*$")
HEADER_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
RESERVED = {"_load_order"}


class AuthoredFileError(ValueError):
    """An authored CSV that cannot be loaded; the message names the file and the problem."""


def list_authored_files(root: Path) -> list[Path]:
    """Every CSV in `<root>/authored`, sorted by name. A missing folder means none."""
    folder = root / AUTHORED_DIR
    return sorted(folder.glob("*.csv")) if folder.is_dir() else []


def read_authored(path: Path) -> tuple[list[str], list[list[str]]]:
    """Header and data rows of one authored file, checked.

    The file is UTF-8 (a byte order mark is accepted). Blank lines are skipped. The header names must
    be plain identifiers, unique ignoring case, and not `_load_order`; each data row must have exactly
    as many fields as the header.
    """
    if not STEM_RE.match(path.stem):
        raise AuthoredFileError(f"{path.name}: the file name must be lower case letters, digits and underscores")
    with path.open(encoding="utf-8-sig", newline="") as fh:
        reader = csv.reader(fh)
        try:
            header = [h.strip() for h in next(reader)]
        except StopIteration:
            raise AuthoredFileError(f"{path.name}: the file is empty (a header row is required)") from None
        seen: set[str] = set()
        for name in header:
            if name.lower() in RESERVED:
                raise AuthoredFileError(f"{path.name}: header {name!r} is reserved")
            if not HEADER_RE.match(name):
                raise AuthoredFileError(f"{path.name}: header {name!r} is not a plain identifier")
            if name.lower() in seen:
                raise AuthoredFileError(f"{path.name}: header {name!r} appears twice")
            seen.add(name.lower())
        rows: list[list[str]] = []
        for fields in reader:
            if not fields:
                continue
            if len(fields) != len(header):
                raise AuthoredFileError(
                    f"{path.name}: line {reader.line_num} has {len(fields)} fields, the header has {len(header)}"
                )
            rows.append(fields)
    return header, rows


def create_sql(stem: str, header: list[str]) -> str:
    cols = ",\n    ".join(f"{quote_name(h)} nvarchar(max) NOT NULL" for h in header)
    return (
        f"CREATE TABLE authored.{quote_name(stem)} (\n"
        f"    _load_order int NOT NULL CONSTRAINT {quote_name('pk_authored_' + stem)} PRIMARY KEY,\n"
        f"    {cols}\n);"
    )


def description(stem: str) -> str:
    return (
        f"AUTHORED data, loaded as text from authored/{stem}.csv. It is not source data and is never "
        "part of a real total. Typing and checks are in the SQL that reads it."
    )


def load_one(ctx: StageContext, path: Path) -> int:
    stem = path.stem
    header, rows = read_authored(path)
    ctx.db.execute(f"DROP TABLE IF EXISTS authored.{quote_name(stem)};")
    ctx.db.execute(create_sql(stem, header))
    ctx.db.execute(
        "EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = ?, "
        "@level0type = N'SCHEMA', @level0name = N'authored', "
        "@level1type = N'TABLE', @level1name = ?;",
        (description(stem), stem),
    )
    if rows:
        ctx.db.insert_many(
            f"authored.{quote_name(stem)}",
            ["_load_order", *header],
            ([i, *fields] for i, fields in enumerate(rows, start=1)),
        )
    return len(rows)


def run(ctx: StageContext) -> dict[str, int]:
    counts: dict[str, int] = {}
    for path in list_authored_files(ctx.repo_root):
        counts[path.stem] = load_one(ctx, path)
        ctx.log(f"  authored {path.name}: {counts[path.stem]} rows")
    return counts


STAGE = Stage(
    name="authored",
    scope="committed",
    run=run,
    description="every authored/*.csv into authored.<file stem>, as text",
    order=50,
)
