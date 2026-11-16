"""Paths and the declarative source list (data/manifest/sources.yml)."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

SOURCES_FILE = Path("data") / "manifest" / "sources.yml"
FILES_CSV = Path("data") / "manifest" / "files.csv"
DEAD_LINKS_CSV = Path("data") / "manifest" / "dead_links.csv"
COMMITTED_DIR = Path("data") / "committed"
DATA_DIR_ENV = "UKFR_DATA_DIR"


def find_repo_root(start: Path | None = None) -> Path:
    """Walk up from `start` (default: cwd) to the folder that holds data/manifest/sources.yml."""
    env = os.environ.get("UKFR_REPO_ROOT")
    if env:
        return Path(env).resolve()
    candidates = [Path(start or Path.cwd()).resolve()]
    candidates.append(Path(__file__).resolve())
    for c in candidates:
        for p in [c, *c.parents]:
            if (p / SOURCES_FILE).is_file():
                return p
    raise SystemExit(f"cannot find {SOURCES_FILE.as_posix()} above {candidates[0]}")


def data_dir(repo_root: Path) -> Path:
    """Where fetched (not committed) files live: $UKFR_DATA_DIR or <repo root>/data/raw."""
    env = os.environ.get(DATA_DIR_ENV)
    return Path(env) if env else repo_root / "data" / "raw"


@dataclass
class FileRule:
    """First matching rule decides what happens to a discovered file."""

    match: str = ".*"  # regex on the file name
    title: str | None = None  # optional regex on the attachment title
    action: str = "fetch"  # fetch | catalogue | skip
    tier: int = 1  # within a release, only the lowest tier present is fetched
    note: str = ""

    def matches(self, filename: str, title: str) -> bool:
        if not re.search(self.match, filename or ""):
            return False
        if self.title is not None and not re.search(self.title, title or ""):
            return False
        return True


@dataclass
class ReleaseRule:
    """How a release label is derived from a page: regex groups poured into a template."""

    source: str = "title"  # title | path | filename | value
    pattern: str = ""
    template: str = ""
    value: str = ""


@dataclass
class Discovery:
    kind: str  # page | collection | url | html_index
    target: str  # page path, collection path, fixed URL or index URL
    release: ReleaseRule
    files: list[FileRule] | None = None
    group: str | None = None  # collection group title
    path_regex: str | None = None
    title_regex: str | None = None
    link_regex: str | None = None  # html_index: regex on href
    since: str | None = None  # minimum release label (string compare)
    until: str | None = None
    latest: int | None = None  # keep only the N most recently updated documents
    filename: str | None = None  # url: file name to save as
    page_url: str | None = None  # url: the page a reader should look at
    publication_date_from_csv: bool = False  # url: read "Release date" line of an ONS CSV


@dataclass
class KnownGap:
    release: str
    note: str


@dataclass
class Source:
    id: str
    title: str
    publisher: str
    licence: str
    discover: list[Discovery]
    files: list[FileRule] = field(default_factory=list)
    fetch: bool = True
    commit: bool = False
    volatile: bool = False
    prefer_only_if: str = ""  # regex a preferred-tier file (or a zip member) must match to stand in for the rest
    known_gaps: list[KnownGap] = field(default_factory=list)
    used_for: str = ""

    @property
    def target(self) -> str:
        """Folder name under data/committed or $UKFR_DATA_DIR."""
        return self.id


@dataclass
class Settings:
    user_agent: str
    min_interval: float
    commit_limit_mb: float
    sources: list[Source]

    def source(self, sid: str) -> Source:
        for s in self.sources:
            if s.id == sid:
                return s
        raise KeyError(sid)


def _rules(items: list[dict[str, Any]] | None) -> list[FileRule] | None:
    if items is None:
        return None
    return [FileRule(**i) for i in items]


def _release(d: dict[str, Any] | None) -> ReleaseRule:
    d = dict(d or {})
    if "from" in d:
        d["source"] = d.pop("from")
    return ReleaseRule(**d)


def _discovery(d: dict[str, Any]) -> Discovery:
    d = dict(d)
    kinds = [k for k in ("page", "collection", "url", "html_index") if k in d]
    if len(kinds) != 1:
        raise ValueError(f"discovery entry needs exactly one of page/collection/url/html_index: {d}")
    kind = kinds[0]
    target = d.pop(kind)
    release = _release(d.pop("release", None))
    files = _rules(d.pop("files", None))
    return Discovery(kind=kind, target=target, release=release, files=files, **d)


def parse_settings(raw: dict[str, Any]) -> Settings:
    sources = []
    seen = set()
    for s in raw["sources"]:
        s = dict(s)
        if s["id"] in seen:
            raise ValueError(f"duplicate source id {s['id']}")
        seen.add(s["id"])
        discover = [_discovery(d) for d in s.pop("discover")]
        files = _rules(s.pop("files", [])) or []
        gaps = [KnownGap(**g) for g in s.pop("known_gaps", [])]
        sources.append(Source(discover=discover, files=files, known_gaps=gaps, **s))
    return Settings(
        user_agent=raw.get("user_agent", "open-data-fetch/0.1"),
        min_interval=float(raw.get("min_interval_seconds", 1.0)),
        commit_limit_mb=float(raw.get("commit_limit_mb", 60)),
        sources=sources,
    )


def load_settings(repo_root: Path) -> Settings:
    with open(repo_root / SOURCES_FILE, encoding="utf-8") as f:
        return parse_settings(yaml.safe_load(f))
