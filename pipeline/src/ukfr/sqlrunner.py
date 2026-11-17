"""Find and run the T-SQL files under `sql/` in a fixed order discovered by convention.

Layout: `sql/<layer>/<NNN>_<name>.sql`, where `<layer>` is a warehouse schema name and `NNN` is a
three-digit prefix. Files run layer by layer in `LAYER_ORDER`, then by prefix. Nothing lists the
files: adding one means adding it to the folder.

Phases. Landing tables (`raw`, `quarantine`) must exist before a load stage writes to them, and
everything derived from the loaded data must run after. A file is in phase `pre` or `post`:
`raw` and `quarantine` files default to `pre`, every other layer to `post`; a comment line near the
top of a file overrides that with `-- phase: pre` or `-- phase: post`. `pre` files must be safe to
run again without losing data (`IF OBJECT_ID(...) IS NULL CREATE TABLE ...`); `post` files rebuild
what they own (`DROP ... IF EXISTS`, then create).

Scope. `-- scope: full` in the header marks a file that needs data that is not in git; the default
is `committed`.

`sql/tests/` holds invariant checks (a query that returns the offending rows); the build never runs
them and pytest does.

Batches. A line holding only `GO` (optionally with a count, which is ignored) separates batches, the
way `sqlcmd` reads it. The split is by line, so `GO` inside a string literal or block comment on a
line of its own would be split too; do not write that.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

LAYER_ORDER = ("raw", "quarantine", "authored", "synthetic", "stg", "dw", "scale", "audit")
PRE_BY_DEFAULT = frozenset({"raw", "quarantine"})
TESTS_DIR = "tests"
SCOPES = ("committed", "full")

_FILE_RE = re.compile(r"^(\d{3})_([a-z0-9][a-z0-9_]*)\.sql$")
_GO_RE = re.compile(r"^\s*GO(?:\s+\d+)?\s*(?:--.*)?$", re.IGNORECASE)
_HEADER_RE = re.compile(r"^\s*--\s*(phase|scope|test|marker|requires)\s*:\s*(.+?)\s*$", re.IGNORECASE)


class SqlLayoutError(ValueError):
    """The sql/ folder breaks the naming convention."""


class SqlRunError(RuntimeError):
    """A batch failed. The message names the file, the batch and its first line."""


@dataclass(frozen=True)
class SqlFile:
    layer: str
    number: int
    name: str
    path: Path
    phase: str  # pre | post
    scope: str  # committed | full

    @property
    def rel(self) -> str:
        return f"{self.layer}/{self.path.name}"


@dataclass(frozen=True)
class Batch:
    text: str
    line: int  # 1-based line of the batch's first line in the file


def split_batches(text: str) -> list[Batch]:
    """Split on `GO` lines. Empty batches (only whitespace or comments between two GOs) are kept
    out; every other batch carries the line it starts on."""
    batches: list[Batch] = []
    current: list[str] = []
    start = 1

    def flush() -> None:
        joined = "\n".join(current)
        body = joined.strip("\n")
        if body.strip() and not _only_comments(body):
            batches.append(Batch(body, start + len(joined) - len(joined.lstrip("\n"))))

    for number, line in enumerate(text.splitlines(), start=1):
        if _GO_RE.match(line):
            flush()
            current = []
            start = number + 1
        else:
            if not current:
                start = number
            current.append(line)
    flush()
    return batches


def _only_comments(body: str) -> bool:
    stripped = re.sub(r"/\*.*?\*/", "", body, flags=re.DOTALL)
    return all(not ln.strip() or ln.strip().startswith("--") for ln in stripped.splitlines())


def header_directives(text: str, limit: int = 12) -> dict[str, str]:
    """`-- key: value` lines among the first `limit` lines (phase, scope, test, marker, requires)."""
    found: dict[str, str] = {}
    for line in text.splitlines()[:limit]:
        m = _HEADER_RE.match(line)
        if m:
            found[m.group(1).lower()] = m.group(2).strip()
    return found


def discover(sql_root: Path) -> list[SqlFile]:
    """Every build file under `sql_root`, in the order they run (pre files before post files, each
    by layer then prefix). Raises `SqlLayoutError` for an unknown folder, a badly named file or a
    prefix used twice in one layer."""
    if not sql_root.is_dir():
        raise SqlLayoutError(f"{sql_root} is not a folder")
    files: list[SqlFile] = []
    for entry in sorted(sql_root.iterdir()):
        if entry.is_file():
            if entry.suffix.lower() == ".sql":
                raise SqlLayoutError(f"{entry}: SQL files belong in a layer folder ({', '.join(LAYER_ORDER)})")
            continue
        if entry.name == TESTS_DIR:
            continue
        if entry.name not in LAYER_ORDER:
            raise SqlLayoutError(f"{entry}: unknown layer folder; expected one of {', '.join(LAYER_ORDER)}")
        seen: dict[int, Path] = {}
        for p in sorted(entry.glob("*")):
            if p.is_dir():
                raise SqlLayoutError(f"{p}: layer folders are flat")
            if p.suffix.lower() != ".sql":
                continue
            m = _FILE_RE.match(p.name)
            if not m:
                raise SqlLayoutError(f"{p}: name must look like 010_object_name.sql (three digits, lower case)")
            number = int(m.group(1))
            if number in seen:
                raise SqlLayoutError(f"{p} and {seen[number].name} use prefix {number:03d} in layer {entry.name}")
            seen[number] = p
            d = header_directives(p.read_text(encoding="utf-8"))
            phase = d.get("phase", "pre" if entry.name in PRE_BY_DEFAULT else "post").lower()
            scope = d.get("scope", "committed").lower()
            if phase not in ("pre", "post"):
                raise SqlLayoutError(f"{p}: phase must be pre or post, got {phase!r}")
            if scope not in SCOPES:
                raise SqlLayoutError(f"{p}: scope must be committed or full, got {scope!r}")
            files.append(SqlFile(entry.name, number, m.group(2), p, phase, scope))
    order = {name: i for i, name in enumerate(LAYER_ORDER)}
    return sorted(files, key=lambda f: (order[f.layer], f.number))


def select(files: list[SqlFile], phase: str, scope: str) -> list[SqlFile]:
    """The files of one phase that the chosen build scope includes (`full` includes `committed`)."""
    if scope not in SCOPES:
        raise ValueError(f"scope must be one of {SCOPES}")
    allowed = {"committed"} if scope == "committed" else {"committed", "full"}
    return [f for f in files if f.phase == phase and f.scope in allowed]


def run_file(db, f: SqlFile) -> int:
    """Run every batch of one file. Returns the batch count. Stops at the first failure."""
    batches = split_batches(f.path.read_text(encoding="utf-8"))
    for n, b in enumerate(batches, start=1):
        try:
            db.execute(b.text)
        except Exception as exc:
            first = next((ln.strip() for ln in b.text.splitlines() if ln.strip()), "")
            raise SqlRunError(
                f"{f.rel} batch {n} of {len(batches)} (line {b.line}, starts: {first[:80]!r}): {exc}"
            ) from exc
    return len(batches)


def run_files(db, files: list[SqlFile], log=print) -> None:
    for f in files:
        n = run_file(db, f)
        log(f"  sql {f.rel} ({n} batch{'es' if n != 1 else ''})")


def collect_test_files(sql_root: Path) -> list[Path]:
    """The invariant checks under `sql/tests/`, sorted by path."""
    root = sql_root / TESTS_DIR
    return sorted(root.rglob("*.sql")) if root.is_dir() else []
