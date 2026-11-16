"""`ukfr fetch`: discover, download, and write the manifest."""

from __future__ import annotations

import os
import re
import zipfile
from dataclasses import dataclass, field, replace
from pathlib import Path

from . import zipstream
from .config import COMMITTED_DIR, DEAD_LINKS_CSV, FILES_CSV, Settings, Source, data_dir
from .discover import discover
from .http import DEAD_STATUS, Client, sha256_file
from .manifest import RAW_PREFIX, DeadLink, Row, merge, read_dead, read_rows, write_dead, write_rows
from .select import Planned, plan


@dataclass
class Summary:
    rows: list[Row] = field(default_factory=list)
    dead: list[DeadLink] = field(default_factory=list)
    downloaded: int = 0
    skipped: int = 0
    catalogued: int = 0
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


def local_path(repo_root: Path, raw_root: Path, source: Source, release: str, filename: str) -> tuple[Path, str]:
    """Absolute path to write to, and the portable form recorded in the manifest."""
    rel = Path(source.target) / release / filename
    if source.commit:
        return repo_root / COMMITTED_DIR / rel, (COMMITTED_DIR / rel).as_posix()
    return raw_root / rel, RAW_PREFIX + rel.as_posix()


def resolve(repo_root: Path, raw_root: Path, recorded: str) -> Path:
    if recorded.startswith(RAW_PREFIX):
        return raw_root / recorded[len(RAW_PREFIX) :]
    return repo_root / recorded


def _ons_release_date(path: Path) -> str:
    """ONS generator CSVs carry a line like "Release date","21-10-2026"."""
    try:
        with open(path, encoding="utf-8-sig", errors="replace") as f:
            for _ in range(12):
                line = f.readline()
                m = re.match(r'"Release date","(\d{2})-(\d{2})-(\d{4})"', line)
                if m:
                    return f"{m.group(3)}-{m.group(2)}-{m.group(1)}"
    except OSError:
        pass
    return ""


def _zip_members(path: Path) -> str:
    if path.suffix.lower() != ".zip" or not zipfile.is_zipfile(path):
        return ""
    try:
        return zipstream.describe(path)
    except zipfile.BadZipFile as e:
        return f"unreadable: {e}"


def _base_row(p: Planned) -> Row:
    c = p.cand
    return Row(
        source_id=c.source_id,
        release=c.release,
        first_published=c.first_published,
        public_updated=c.public_updated,
        page_url=c.page_url,
        file_url=c.file_url,
        filename=c.filename,
        title=c.title,
        content_type=c.content_type,
        bytes="" if c.api_bytes is None else str(c.api_bytes),
        sha256="",
        fetched="no",
        http_status="",
        path="",
        notes=p.note,
        zip_members="",
    )


def _add_note(row: Row, text: str) -> None:
    row.notes = f"{row.notes}; {text}" if row.notes else text


def fetch_source(
    source: Source,
    settings: Settings,
    client: Client,
    repo_root: Path,
    raw_root: Path,
    old_rows: list[Row],
    summary: Summary,
    catalogue_only: bool = False,
    accept_changes: bool = False,
    log=print,
) -> list[Row]:
    disc = discover(source, client)
    planned = plan(source, disc.candidates)
    for prob in disc.problems:
        summary.dead.append(DeadLink(source.id, "", prob.page_url, prob.url, "", str(prob.status), prob.note))
        summary.warnings.append(f"{source.id}: {prob.note}: {prob.url} ({prob.status})")

    # Pages that yielded nothing to fetch: either a known gap (note) or a warning.
    gaps = {g.release: g.note for g in source.known_gaps}
    fetch_releases = {p.cand.release for p in planned if p.action == "fetch"}
    for idx, release, page_url in sorted(set(disc.pages)):
        if not source.fetch or release in fetch_releases:
            continue
        d = source.discover[idx]
        rules = d.files if d.files is not None else source.files
        if not any(r.action == "fetch" for r in rules):
            continue
        if release in gaps:
            summary.notes.append(f"{source.id} {release}: {gaps[release]}")
        else:
            summary.warnings.append(f"{source.id} {release}: no file matched the fetch rules on {page_url}")
    for release, note in gaps.items():
        if release not in {r for _, r, _ in disc.pages}:
            summary.notes.append(f"{source.id} {release}: {note}")

    if source.commit:
        total = sum((p.cand.api_bytes or 0) for p in planned if p.action == "fetch")
        if total > settings.commit_limit_mb * 1_000_000:
            summary.errors.append(
                f"{source.id}: committed files would total {total / 1e6:.1f} MB, over the "
                f"{settings.commit_limit_mb:.0f} MB limit; nothing downloaded"
            )
            return [r for r in old_rows if r.source_id == source.id]

    by_url = {r.file_url: r for r in old_rows if r.source_id == source.id}
    by_name = {(r.release, r.filename): r for r in old_rows if r.source_id == source.id}
    ctx = _Ctx(source, client, repo_root, raw_root, summary, accept_changes, log)
    rows: list[Row] = []
    deferred: list[tuple[Planned, Row | None]] = []
    for p in sorted(planned, key=lambda x: (x.cand.release, x.cand.filename)):
        old = by_url.get(p.cand.file_url) or by_name.get((p.cand.release, p.cand.filename))
        if p.superseded and source.prefer_only_if and not catalogue_only:
            deferred.append((p, old))
        elif p.action == "catalogue" or catalogue_only:
            rows.append(_catalogue_one(ctx, p, old))
        else:
            rows.append(_fetch_one(ctx, p, old))

    # A lower-tier file only stands in for the other formats if it holds what `prefer_only_if`
    # asks for (for OSCAR: a CSV). Otherwise the superseded files of that release are fetched too.
    satisfied = {r.release for r in rows if r.fetched == "yes" and _holds(r, source.prefer_only_if)}
    for p, old in deferred:
        if p.cand.release in satisfied:
            rows.append(_catalogue_one(ctx, p, old))
        else:
            p.action = "fetch"
            p.note = (
                "fetched as well: the preferred file of this release holds no file matching " + source.prefer_only_if
            )
            rows.append(_fetch_one(ctx, p, old))
    return rows


def _holds(row: Row, pattern: str) -> bool:
    if re.search(pattern, row.filename):
        return True
    return any(re.search(pattern, m.split("|", 1)[0]) for m in row.zip_members.split(";") if m)


@dataclass
class _Ctx:
    source: Source
    client: Client
    repo_root: Path
    raw_root: Path
    summary: Summary
    accept_changes: bool
    log: object


def _dead(ctx: _Ctx, p: Planned, status: int, note: str) -> None:
    c = p.cand
    ctx.summary.dead.append(DeadLink(ctx.source.id, c.release, c.page_url, c.file_url, c.filename, str(status), note))


def _catalogue_one(ctx: _Ctx, p: Planned, old: Row | None) -> Row:
    c = p.cand
    row = _base_row(p)
    if p.action == "fetch" and old and old.sha256 and old.fetched == "yes":
        # A catalogue-only rerun keeps what an earlier fetch recorded.
        return replace(
            old,
            first_published=row.first_published,
            public_updated=row.public_updated,
            page_url=row.page_url,
            title=row.title,
            notes=row.notes,
        )
    status, size = ctx.client.head(c.file_url)
    row.http_status = str(status)
    # gov.uk HTML pages are rendered per request and their length drifts; leave it blank.
    if not row.bytes and size is not None and row.content_type != "text/html":
        row.bytes = str(size)
    if status in DEAD_STATUS:
        row.fetched = "dead"
        _dead(ctx, p, status, "catalogue-only file not served")
    elif status != 200:
        ctx.summary.warnings.append(f"{ctx.source.id}: HEAD {c.file_url} returned {status}")
    if p.action == "fetch":
        row.notes = row.notes or "not downloaded in this run (--catalogue-only)"
    ctx.summary.catalogued += 1
    return row


def _fetch_one(ctx: _Ctx, p: Planned, old: Row | None) -> Row:
    c, source, summary = p.cand, ctx.source, ctx.summary
    row = _base_row(p)
    dest, recorded = local_path(ctx.repo_root, ctx.raw_root, source, c.release, c.filename)

    # Resume: the file is already on disk with the recorded hash. Volatile files are always refetched.
    if not source.volatile and old and old.sha256 and dest.is_file() and sha256_file(dest) == old.sha256:
        row.sha256, row.bytes, row.fetched, row.path = old.sha256, old.bytes, "yes", recorded
        row.http_status = old.http_status or "200"
        row.zip_members = old.zip_members
        row.content_type = row.content_type or old.content_type
        summary.skipped += 1
        return row

    ctx.log(f"  get {source.id}/{c.release}/{c.filename}")
    dl = ctx.client.download(c.file_url, dest)
    part = dest.with_name(dest.name + ".part")
    row.http_status = str(dl.status)
    if dl.status in DEAD_STATUS:
        row.fetched = "dead"
        _dead(ctx, p, dl.status, "listed on the page but not served")
        return row
    if dl.status != 200:
        summary.errors.append(f"{source.id}: GET {c.file_url} returned {dl.status}")
        return old if old else row

    if old and old.sha256 and old.sha256 != dl.sha256:
        msg = f"{source.id}/{c.release}/{c.filename} changed at source: sha256 {old.sha256[:12]} -> {dl.sha256[:12]}"
        if source.volatile:
            summary.warnings.append(msg + " (volatile source, accepted)")
        elif ctx.accept_changes:
            summary.warnings.append(msg + " (accepted with --accept-changes)")
        else:
            part.unlink(missing_ok=True)
            summary.errors.append(msg + "; kept the recorded version. Rerun with --accept-changes to take it.")
            return old

    os.replace(part, dest)
    row.sha256, row.bytes, row.fetched, row.path = dl.sha256, str(dl.bytes), "yes", recorded
    row.content_type = row.content_type or dl.content_type
    row.zip_members = _zip_members(dest)
    if source.volatile:
        _add_note(row, "volatile: regenerated by the publisher on each request")
        rd = _ons_release_date(dest)
        if rd:
            row.public_updated = rd
    summary.downloaded += 1
    return row


def run_fetch(
    repo_root: Path,
    settings: Settings,
    client: Client,
    source_ids: list[str] | None = None,
    catalogue_only: bool = False,
    accept_changes: bool = False,
    log=print,
) -> Summary:
    raw_root = data_dir(repo_root)
    sources = [settings.source(s) for s in source_ids] if source_ids else settings.sources
    files_csv = repo_root / FILES_CSV
    dead_csv = repo_root / DEAD_LINKS_CSV
    old_rows = read_rows(files_csv)
    summary = Summary()
    new_rows: list[Row] = []
    for s in sources:
        log(f"{s.id}: discovering")
        rows = fetch_source(
            s,
            settings,
            client,
            repo_root,
            raw_root,
            old_rows,
            summary,
            catalogue_only=catalogue_only,
            accept_changes=accept_changes,
            log=log,
        )
        new_rows.extend(rows)
    done = {s.id for s in sources}
    all_rows = merge(old_rows, new_rows, done)
    write_rows(files_csv, all_rows)
    write_dead(dead_csv, merge(read_dead(dead_csv), summary.dead, done))
    summary.rows = all_rows
    return summary
