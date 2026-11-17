"""Command line: `ukfr fetch`, `ukfr build`, `ukfr control`, `ukfr profile` and `ukfr zip-head`."""

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
    if args.what in ("inyear", "bud", "all"):
        from .profile import bud, inyear

        if args.what != "bud":
            inyear.run(root)
        if args.what != "inyear":
            bud.run(root)  # reads inyear's BEIS output, so it runs after it
    return 0


def _build(args) -> int:
    from . import build as buildmod
    from .db import DbSettings
    from .stages import all_stages

    if args.list_stages:
        for s in all_stages():
            print(f"{s.name:20} scope={s.scope:9} {s.description}")
        return 0
    root = find_repo_root()
    settings = DbSettings.from_env()
    if args.recreate and buildmod.is_main_database(settings) and not args.yes:
        print(
            f"--recreate would drop database {settings.database}; pass --yes or set UKFR_SQL_DATABASE",
            file=sys.stderr,
        )
        return 2
    try:
        buildmod.build(
            settings,
            root,
            scope=args.scope,
            stage_names=args.stage,
            recreate=args.recreate,
            skip_sql=args.skip_sql,
            audit_dir=args.audit_dir,
            wait_seconds=args.wait,
        )
    except (ValueError, RuntimeError) as exc:
        print(f"build failed: {exc}", file=sys.stderr)
        return 1
    return 0


def _control(args) -> int:
    root = find_repo_root()
    if args.what == "inyear":
        from .controls import inyear_independent

        path = inyear_independent.run(root, args.out)
    else:
        from .controls import bud_independent

        path = (bud_independent.run_bud if args.what == "bud" else bud_independent.run_pss)(root, args.out)
    print(f"wrote {path}")
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
    p.add_argument("what", choices=["extract", "mfo", "plans", "inyear", "bud", "all"])
    p.add_argument("--cache-dir", type=Path, help="keep full-stream scan results here and reuse them")
    p.set_defaults(func=_profile)
    b = sub.add_parser("build", help="create the database, load the sources, run the SQL, write the audit CSVs")
    b.add_argument("--scope", choices=["committed", "full"], default="committed", help="committed: files in git only")
    b.add_argument("--stage", action="append", metavar="NAME", help="run only this load stage (repeatable)")
    b.add_argument("--recreate", action="store_true", help="drop the database first")
    b.add_argument("--yes", action="store_true", help="allow --recreate on the default database name")
    b.add_argument("--skip-sql", action="store_true", help="run the pre SQL and the stages, not the post SQL or audit")
    b.add_argument("--audit-dir", type=Path, help="where the audit CSVs go (default evidence/build)")
    b.add_argument("--wait", type=float, default=0, metavar="SECONDS", help="retry the first login for this long")
    b.add_argument("--list-stages", action="store_true", help="print the load stages and exit")
    b.set_defaults(func=_build)
    c = sub.add_parser("control", help="independent recomputation of source-file controls")
    c.add_argument("what", choices=["inyear", "bud", "pss"])
    c.add_argument("--out", type=Path, help="output CSV (default data/audit/<what>_independent_control.csv)")
    c.set_defaults(func=_control)
    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
