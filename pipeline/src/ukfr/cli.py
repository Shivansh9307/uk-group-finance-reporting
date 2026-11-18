"""Command line: fetch, build, build-summary, control, inventory, real-totals, negative-control, profile, zip-head."""

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


def _real_totals(args) -> int:
    from . import real_totals
    from .db import Db, DbSettings

    root = find_repo_root()
    path = root / real_totals.EXPECTED_CSV
    with Db(DbSettings.from_env()) as db:
        scope = real_totals.build_scope(db)
        measured = real_totals.measure(db, scope)
    for r in measured:
        print(f"{scope}: {r['fact']} {r['rows']} rows, sum {r['amount_sum']}")
    if args.write:
        real_totals.write_expected(path, scope, measured)
        print(f"wrote {path.relative_to(root).as_posix()} ({scope} rows)")
    return 0


def _negative_control(args) -> int:
    from . import negative_control

    return negative_control.run()


def _build_summary(args) -> int:
    from . import build_summary

    root = find_repo_root()
    try:
        written = build_summary.write_all(
            args.build_log,
            args.pytest_log,
            args.out_dir or root / "evidence" / "full",
            args.table_counts,
            require_clean=not args.allow_skips,
        )
    except build_summary.SummaryError as exc:
        print(f"build-summary: {exc}", file=sys.stderr)
        return 1
    for p in written:
        print(f"wrote {p}")
    return 0


def _inventory(args) -> int:
    from . import inventory

    root = find_repo_root()
    if args.write:
        path = inventory.write_doc(root)
        print(f"wrote the inventory block of {path.relative_to(root).as_posix()}")
    problems = inventory.problems(root)
    for p in problems:
        print("PROBLEM:", p, file=sys.stderr)
    print(inventory.render_text(root))
    return 1 if problems else 0


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
    t = sub.add_parser("real-totals", help="print the row counts and sums of the real facts; --write pins them")
    t.add_argument("--write", action="store_true", help="write evidence/expected/real_fact_totals.csv for this scope")
    t.set_defaults(func=_real_totals)
    i = sub.add_parser("inventory", help="list every SQL assertion and Python control; fail on a test without a header")
    i.add_argument("--write", action="store_true", help="rewrite the generated block of docs/reconciliation.md")
    i.set_defaults(func=_inventory)
    s = sub.add_parser("build-summary", help="write the committed summary of a full build log and a test run")
    s.add_argument("--build-log", type=Path, required=True, help="the output of `ukfr build --scope full`")
    s.add_argument("--pytest-log", type=Path, required=True, help="the output of `pytest -q`")
    s.add_argument("--table-counts", type=Path, help="evidence/build/table_counts.csv written by that build")
    s.add_argument("--out-dir", type=Path, help="default evidence/full")
    s.add_argument("--allow-skips", action="store_true", help="do not require zero skips and zero failures")
    s.set_defaults(func=_build_summary)
    n = sub.add_parser(
        "negative-control",
        help="plant wrong numbers in the database UKFR_SQL_DATABASE names and require the control tests to fail",
    )
    n.set_defaults(func=_negative_control)
    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
