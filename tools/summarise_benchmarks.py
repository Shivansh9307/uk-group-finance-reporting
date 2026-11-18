#!/usr/bin/env python3
"""Summarise dscmd benchmark files into one CSV: median, min and max per query and cache state.

    python tools/summarise_benchmarks.py                      # evidence/perf/naive -> evidence/perf/naive/summary.csv
    python tools/summarise_benchmarks.py --dir evidence/perf/rewritten --markdown

Each input file is what `tools/run_dax.ps1 -Benchmark` writes for one query: one row per run (cold-cache runs, then
warm-cache runs), then a `# Summary` block that this script ignores because it recomputes from the runs.

dscmd sometimes returns a run whose trace events were missed: the total duration is there and the storage-engine
query count, the storage-engine time and the formula-engine time are all zero. The total is always used. The split
and the query count are taken from the runs that have events (query count above zero), and the summary says how many
runs that is, so a reader can see how much the split rests on.

Timings rank queries against each other on one machine; they are not absolute figures.
"""
from __future__ import annotations

import argparse
import csv
import io
import statistics
from pathlib import Path

DEFAULT_DIR = Path(__file__).resolve().parents[1] / "evidence" / "perf" / "naive"
COLUMNS = [
    "query",
    "cache",
    "runs",
    "total_ms_median",
    "total_ms_min",
    "total_ms_max",
    "runs_with_events",
    "formula_engine_ms_median",
    "storage_engine_ms_median",
    "storage_engine_queries_median",
    "rows",
    "errors",
]


def read_runs(path: Path) -> list[dict[str, str]] | None:
    text = path.read_text(encoding="utf-8-sig")
    if "Sequence,Cache" not in text:
        return None
    return list(csv.DictReader(io.StringIO(text.split("# Summary")[0].strip())))


def med(values: list[float]) -> float | None:
    return statistics.median(values) if values else None


def summarise(directory: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for path in sorted(directory.glob("*.csv")):
        if path.name == "summary.csv":
            continue
        runs = read_runs(path)
        if runs is None:
            continue
        for cache in ("Cold", "Warm"):
            r = [x for x in runs if x["Cache"] == cache]
            if not r:
                continue
            total = [float(x["TotalDuration_ms"]) for x in r]
            ev = [x for x in r if float(x["StorageEngineQueryCount"]) > 0]
            rows.append(
                {
                    "query": path.stem,
                    "cache": cache.lower(),
                    "runs": len(r),
                    "total_ms_median": med(total),
                    "total_ms_min": min(total),
                    "total_ms_max": max(total),
                    "runs_with_events": len(ev),
                    "formula_engine_ms_median": med([float(x["FormulaEngineDuration_ms"]) for x in ev]),
                    "storage_engine_ms_median": med([float(x["StorageEngineDuration_ms"]) for x in ev]),
                    "storage_engine_queries_median": med([float(x["StorageEngineQueryCount"]) for x in ev]),
                    "rows": int(float(r[0]["RowCount"])),
                    "errors": sum(1 for x in r if x.get("Error")),
                }
            )
    return rows


def fmt(v: object) -> str:
    if v is None:
        return ""
    if isinstance(v, float):
        return f"{v:g}"
    return str(v)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dir", type=Path, default=DEFAULT_DIR, help="folder with the benchmark CSVs")
    ap.add_argument("--out", type=Path, default=None, help="summary CSV (default: <dir>/summary.csv)")
    ap.add_argument("--markdown", action="store_true", help="print a Markdown table instead of writing the CSV")
    args = ap.parse_args()
    rows = summarise(args.dir)
    if not rows:
        raise SystemExit(f"no benchmark files in {args.dir}")
    if args.markdown:
        print("| " + " | ".join(COLUMNS) + " |")
        print("|" + "|".join(["---"] + ["---:"] * (len(COLUMNS) - 1)) + "|")
        for r in rows:
            print("| " + " | ".join(fmt(r[c]) for c in COLUMNS) + " |")
        return
    out = args.out or args.dir / "summary.csv"
    with out.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(COLUMNS)
        for r in rows:
            w.writerow([fmt(r[c]) for c in COLUMNS])
    print(f"{len(rows)} rows -> {out.name}")


if __name__ == "__main__":
    main()
