"""`ukfr fetch --verify`: offline check of every fetched file against the recorded sha256."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from .config import COMMITTED_DIR, FILES_CSV, Settings, data_dir
from .fetch import resolve
from .http import sha256_file
from .manifest import read_rows


@dataclass
class VerifyResult:
    committed_ok: int = 0
    raw_ok: int = 0
    not_present: int = 0
    dead: int = 0
    catalogue: int = 0
    volatile_changed: int = 0
    failures: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.failures

    def line(self) -> str:
        return (
            f"verify: {self.committed_ok} committed files ok, {self.raw_ok} raw files ok, "
            f"{self.not_present} not present locally, {self.dead} dead, {self.catalogue} catalogue-only, "
            f"{self.volatile_changed} volatile changed, {len(self.failures)} failures"
        )


def verify(repo_root: Path, settings: Settings) -> VerifyResult:
    raw_root = data_dir(repo_root)
    volatile = {s.id for s in settings.sources if s.volatile}
    res = VerifyResult()
    committed_prefix = COMMITTED_DIR.as_posix() + "/"
    rows = read_rows(repo_root / FILES_CSV)
    if not rows:
        res.failures.append(f"{FILES_CSV.as_posix()} is missing or empty")
    for r in rows:
        if r.fetched == "dead":
            res.dead += 1
            continue
        if r.fetched != "yes":
            res.catalogue += 1
            continue
        if not r.sha256 or not r.path:
            res.failures.append(f"{r.source_id}/{r.release}/{r.filename}: fetched but no sha256 or path recorded")
            continue
        committed = r.path.startswith(committed_prefix)
        path = resolve(repo_root, raw_root, r.path)
        if not path.is_file():
            if committed:
                res.failures.append(f"missing committed file {r.path}")
            else:
                res.not_present += 1
            continue
        actual = sha256_file(path)
        if actual != r.sha256:
            msg = f"{r.path}: sha256 {actual[:12]} does not match the manifest {r.sha256[:12]}"
            if r.source_id in volatile:
                res.volatile_changed += 1
                res.warnings.append(msg + " (volatile source; refetch to update)")
            else:
                res.failures.append(msg)
            continue
        if committed:
            res.committed_ok += 1
        else:
            res.raw_ok += 1

    # Files under data/committed that the manifest does not know about are a failure too.
    known = {r.path for r in rows if r.path.startswith(committed_prefix)}
    root = repo_root / COMMITTED_DIR
    if root.is_dir():
        for p in sorted(root.rglob("*")):
            if p.is_file() and not p.name.startswith(".") and p.suffix != ".part":
                rel = p.relative_to(repo_root).as_posix()
                if rel not in known:
                    res.failures.append(f"{rel} is committed but not in the manifest")
    return res
