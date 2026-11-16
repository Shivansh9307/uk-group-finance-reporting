"""Command line: `ukfr fetch` and `ukfr zip-head`."""

from __future__ import annotations

import argparse
import sys
from collections import Counter
from pathlib import Path

from . import zipstream
from .config import find_repo_root, load_settings
from .fetch import run_fetch
from .http import Client
from .verify import verify


def _fetch(args) -> int:
    root = find_repo_root()
    settings = load_settings(root)
    if args.verify:
        res = verify(root, settings)
        for w in res.warnings:
            print("warning:", w)
        for f in res.failures:
            print("FAIL:", f)
        print(res.line())
        return 0 if res.ok else 1
    known = {s.id for s in settings.sources}
    bad = [s for s in args.source or [] if s not in known]
    if bad:
        print(f"unknown source id(s): {', '.join(bad)}; known: {', '.join(sorted(known))}", file=sys.stderr)
        return 2
    client = Client(settings.user_agent, min_interval=settings.min_interval)
    try:
        summary = run_fetch(
            root,
            settings,
            client,
            source_ids=args.source,
            catalogue_only=args.catalogue_only,
            accept_changes=args.accept_changes,
        )
    finally:
        client.close()
    for n in summary.notes:
        print("note:", n)
    for w in summary.warnings:
        print("warning:", w)
    for e in summary.errors:
        print("ERROR:", e)
    counts = Counter((r.source_id, r.fetched) for r in summary.rows)
    for (sid, fetched), n in sorted(counts.items()):
        print(f"  {sid:22} {fetched:5} {n}")
    print(
        f"fetch: {summary.downloaded} downloaded, {summary.skipped} already present, "
        f"{summary.catalogued} catalogue-only, {len(summary.dead)} dead links, "
        f"{len(summary.errors)} errors, {client.requests} requests"
    )
    return 0 if summary.ok else 1


def _zip_head(args) -> int:
    path = Path(args.zip)
    infos = zipstream.members(path)
    for i in infos:
        print(
            f"member {i.filename} method={zipstream.METHOD_NAMES.get(i.compress_type, i.compress_type)} "
            f"compressed={i.compress_size} uncompressed={i.file_size}"
        )
    name = args.member or infos[0].filename
    for line in zipstream.head_lines(path, name, args.lines, encoding=args.encoding):
        print(line)
    return 0


def _profile(args) -> int:
    from .config import data_dir
    from .profile import extract, mfo, plans

    root = find_repo_root()
    raw = data_dir(root)
    if args.what in ("extract", "mfo", "all"):
        scans = extract.run(root, raw, args.cache_dir)
        if args.what != "extract":
            mfo.run(root, raw, args.cache_dir, scans)
    if args.what in ("plans", "all"):
        plans.run(root, raw)
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="ukfr")
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fetch", help="discover and download source files; write data/manifest/files.csv")
    f.add_argument("--source", action="append", metavar="ID", help="only this source (repeatable)")
    f.add_argument("--catalogue-only", action="store_true", help="discover and list files without downloading")
    f.add_argument("--verify", action="store_true", help="offline: recheck sha256 of every fetched file")
    f.add_argument("--accept-changes", action="store_true", help="take files whose content changed at source")
    f.set_defaults(func=_fetch)
    z = sub.add_parser("zip-head", help="print the first lines of a zip member without extracting it")
    z.add_argument("zip")
    z.add_argument("--member")
    z.add_argument("-n", "--lines", type=int, default=5)
    z.add_argument("--encoding", default="utf-8")
    z.set_defaults(func=_zip_head)
    p = sub.add_parser("profile", help="profile source files and write docs/profiling/data and data/audit CSVs")
    p.add_argument("what", choices=["extract", "mfo", "plans", "all"])
    p.add_argument("--cache-dir", type=Path, help="keep full-stream scan results here and reuse them")
    p.set_defaults(func=_profile)
    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
