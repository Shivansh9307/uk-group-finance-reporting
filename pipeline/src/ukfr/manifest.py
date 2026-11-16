"""The file manifest (data/manifest/files.csv) and the dead-link list."""

from __future__ import annotations

import csv
from dataclasses import asdict, dataclass, fields
from pathlib import Path

RAW_PREFIX = "$UKFR_DATA_DIR/"


@dataclass
class Row:
    source_id: str
    release: str
    first_published: str
    public_updated: str
    page_url: str
    file_url: str
    filename: str
    title: str
    content_type: str
    bytes: str  # bytes on disk when fetched, else the size the API or a HEAD request reported
    sha256: str  # blank for catalogue-only files
    fetched: str  # yes | no | dead
    http_status: str
    path: str  # data/committed/... or $UKFR_DATA_DIR/... ; blank when not fetched
    notes: str
    zip_members: str  # name|method|uncompressed bytes, ';'-separated, for fetched zips

    def key(self) -> tuple[str, str, str, str]:
        return (self.source_id, self.release, self.filename, self.file_url)


COLUMNS = [f.name for f in fields(Row)]


@dataclass
class DeadLink:
    source_id: str
    release: str
    page_url: str
    file_url: str
    filename: str
    http_status: str
    note: str

    def key(self) -> tuple[str, str, str, str]:
        return (self.source_id, self.release, self.filename, self.file_url)


DEAD_COLUMNS = [f.name for f in fields(DeadLink)]


def _read(path: Path, cls):
    if not path.is_file():
        return []
    with open(path, encoding="utf-8", newline="") as f:
        return [cls(**{k: (v or "") for k, v in r.items()}) for r in csv.DictReader(f)]


def _write(path: Path, items, columns) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    items = sorted(items, key=lambda r: r.key())
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=columns, lineterminator="\n")
        w.writeheader()
        for r in items:
            w.writerow(asdict(r))


def read_rows(path: Path) -> list[Row]:
    return _read(path, Row)


def write_rows(path: Path, rows: list[Row]) -> None:
    keys = [r.key() for r in rows]
    if len(keys) != len(set(keys)):
        dupes = sorted({k for k in keys if keys.count(k) > 1})
        raise ValueError(f"duplicate manifest rows: {dupes[:5]}")
    _write(path, rows, COLUMNS)


def read_dead(path: Path) -> list[DeadLink]:
    return _read(path, DeadLink)


def write_dead(path: Path, items: list[DeadLink]) -> None:
    _write(path, items, DEAD_COLUMNS)


def merge(existing: list, new: list, replaced_sources: set[str]) -> list:
    """Keep rows of sources that were not part of this run; replace the rest."""
    return [r for r in existing if r.source_id not in replaced_sources] + list(new)
