#!/usr/bin/env python3
"""Compact the JSON that `tools/trace_query.ps1` writes into evidence that is small enough to commit.

    python tools/compact_traces.py <trace folder> evidence/perf/naive/traces

The full traces run to megabytes (every storage-engine query, and the whole physical plan), and hold the machine's
paths in some fields. The compact file keeps what a reader needs to check a claim about a query:

  - the timings and counts: total, formula-engine and storage-engine time, the number of storage-engine queries by kind,
    cache hits, rows returned, errors;
  - the ten longest storage-engine queries with their text, and how many storage-engine queries are the same text
    (a measure that re-runs one scan many times shows as a high repeat count);
  - the first lines of the logical and physical query plan, with the line counts of the whole plan.

Anything that looks like a drive path, the user profile folder or this machine's name or account is removed before the
file is written, and the script stops if one is left. The run time is not kept, so that a rerun on the same model gives
the same file apart from the timings.
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import re
import socket
from pathlib import Path

PLAN_LINES = 40
LONGEST = 10
DRIVE = re.compile(r"[A-Za-z]:[\\/][^\s\"']*")


def scrub_patterns() -> list[re.Pattern[str]]:
    words = {os.environ.get("USERNAME", ""), os.environ.get("USER", ""), os.environ.get("COMPUTERNAME", ""), socket.gethostname()}
    return [re.compile(re.escape(w), re.IGNORECASE) for w in sorted(words) if len(w) >= 3]


def clean(text: str, patterns: list[re.Pattern[str]]) -> str:
    text = DRIVE.sub("<path>", text)
    for p in patterns:
        text = p.sub("<local>", text)
    return text


def compact(trace: dict, patterns: list[re.Pattern[str]]) -> dict:
    se = trace.get("se_queries") or []
    texts = collections.Counter(clean(q.get("xmsql", ""), patterns) for q in se)
    longest = sorted(se, key=lambda q: (-q.get("duration_ms", 0), q.get("xmsql", "")))[:LONGEST]
    plan = trace.get("query_plan") or {}
    out = {
        "query_file": Path(trace["query_file"]).name,
        "query_sha256": trace["query_sha256"],
        "cold_cache": trace["cold"],
        "rows_returned": trace["rows_returned"],
        "error": trace["error"],
        "total_ms": trace["total_ms"],
        "total_cpu_ms": trace["total_cpu_ms"],
        "storage_engine_ms": trace["se_ms"],
        "formula_engine_ms_derived": trace["fe_ms_derived"],
        "storage_engine_queries": trace["se_query_count"],
        "storage_engine_cache_hits": trace["se_cache_hits"],
        "storage_engine_queries_by_kind": dict(sorted(collections.Counter(q.get("subclass", "") for q in se).items())),
        "distinct_storage_engine_query_texts": len(texts),
        "most_repeated_storage_engine_query": (
            {"times": max(texts.values()), "text": texts.most_common(1)[0][0]} if texts else None
        ),
        "longest_storage_engine_queries": [
            {
                "kind": q.get("subclass", ""),
                "duration_ms": q.get("duration_ms", 0),
                "cached": q.get("cached", False),
                "text": clean(q.get("xmsql", ""), patterns),
            }
            for q in longest
        ],
        "direct_query_events": len(trace.get("direct_query") or []),
        "aggregation_rewrites": len(trace.get("aggregation_rewrites") or []),
        "logical_plan_lines": len((plan.get("logical") or "").splitlines()),
        "physical_plan_lines": len((plan.get("physical") or "").splitlines()),
        "logical_plan_head": [clean(x, patterns) for x in (plan.get("logical") or "").splitlines()[:PLAN_LINES]],
        "physical_plan_head": [clean(x, patterns) for x in (plan.get("physical") or "").splitlines()[:PLAN_LINES]],
    }
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("source", type=Path, help="folder with the full trace JSON files")
    ap.add_argument("target", type=Path, help="folder for the compact files")
    args = ap.parse_args()
    patterns = scrub_patterns()
    args.target.mkdir(parents=True, exist_ok=True)
    n = 0
    for path in sorted(args.source.glob("*.json")):
        trace = json.loads(path.read_text(encoding="utf-8-sig"))
        text = json.dumps(compact(trace, patterns), indent=2, ensure_ascii=False) + "\n"
        leftovers = DRIVE.findall(text.replace("<path>", "")) + [p.pattern for p in patterns if p.search(text)]
        if leftovers:
            raise SystemExit(f"{path.name}: a local path or name is left in the compact file: {leftovers[:3]}")
        (args.target / path.name).write_text(text, encoding="utf-8", newline="\n")
        n += 1
    print(f"{n} compact trace(s) -> {args.target}")


if __name__ == "__main__":
    main()
