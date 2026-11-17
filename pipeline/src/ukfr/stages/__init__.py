"""Load stages: one module per source, found by scanning this package.

A stage module defines one `STAGE = Stage(...)` (or a list called `STAGES`). Adding a source means
adding one module here; nothing else lists it. A stage reads its source files, writes to its own
landing tables (created by `pre` SQL files under `sql/raw` or `sql/quarantine`) and returns a dict
of row counts for the build log. It does no business transformation: that is T-SQL under `sql/`.

Scope: `committed` stages read only files that are in git (what CI builds); `full` stages also read
files under `$UKFR_DATA_DIR`. `--scope full` runs both kinds.
"""

from __future__ import annotations

import importlib
import pkgutil
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from ..db import Db


@dataclass
class StageContext:
    repo_root: Path
    db: Db
    scope: str
    log: Callable[[str], None] = print


@dataclass(frozen=True)
class Stage:
    name: str
    scope: str  # committed | full
    run: Callable[[StageContext], dict[str, int]]
    description: str = ""
    order: int = 100  # lower runs first; ties by name


def all_stages() -> list[Stage]:
    """Every stage in this package, ordered by (order, name)."""
    found: list[Stage] = []
    for info in pkgutil.iter_modules(__path__):
        module = importlib.import_module(f"{__name__}.{info.name}")
        items = getattr(module, "STAGES", None)
        if items is None and hasattr(module, "STAGE"):
            items = [module.STAGE]
        for stage in items or []:
            if stage.scope not in ("committed", "full"):
                raise ValueError(f"stage {stage.name}: scope must be committed or full")
            found.append(stage)
    names = [s.name for s in found]
    dupes = sorted({n for n in names if names.count(n) > 1})
    if dupes:
        raise ValueError(f"duplicate stage names: {dupes}")
    return sorted(found, key=lambda s: (s.order, s.name))


def select_stages(scope: str, names: list[str] | None = None) -> list[Stage]:
    """Stages the scope includes; or exactly the named ones (an error if one is outside the scope)."""
    stages = all_stages()
    by_name = {s.name: s for s in stages}
    if names:
        unknown = [n for n in names if n not in by_name]
        if unknown:
            raise ValueError(f"unknown stage(s) {unknown}; known: {sorted(by_name)}")
        chosen = [by_name[n] for n in names]
        outside = [s.name for s in chosen if s.scope == "full" and scope != "full"]
        if outside:
            raise ValueError(f"stage(s) {outside} need --scope full")
        return sorted(chosen, key=lambda s: (s.order, s.name))
    return [s for s in stages if s.scope == "committed" or scope == "full"]
