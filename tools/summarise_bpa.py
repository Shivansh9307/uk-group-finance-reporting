"""Summarise a Tabular Editor 2 Best Practice Analyzer result (TRX file) into two small CSV files, or check them.

    python tools/summarise_bpa.py --trx bpa-results.trx --write evidence/bpa
    python tools/summarise_bpa.py --trx bpa-results.trx --check evidence/bpa

`bpa_counts.csv` has one row for every rule the run evaluated (rule id, severity, number of objects in violation),
sorted by rule id, so a rule that was added, removed or changed shows up as a difference. `bpa_violations.csv` has
one row for every object in violation (rule id, object type, object name), sorted. Both are written with LF line
endings and hold nothing from the machine that ran the analysis: the TRX file also carries a computer name, a user
name and paths, and none of it is read here. The TRX file itself is never committed.

A rule that Tabular Editor could not evaluate (outcome "Inconclusive", for instance an expression that does not
parse) is an error: the script exits 2 and names the rule. --check exits 1 and prints the differences when the
files on disk do not match the run.

The standard library only, so that it runs on a hosted runner without an environment.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = {"t": "http://microsoft.com/schemas/VisualStudio/TeamTest/2010"}
COUNTS = "bpa_counts.csv"
VIOLATIONS = "bpa_violations.csv"
# `'Deflator' (Table (Import))`, `[Outturn] (Measure)`: the object, then its type, which may carry a qualifier in brackets.
OBJECT_LINE = re.compile(r"^\s+(.*?\S)\s+\(([A-Za-z][A-Za-z ]*(?: \([^()]*\))?)\)\s*$")


def read_trx(path: Path) -> tuple[list[tuple[str, int, int]], list[tuple[str, str, str]], list[str]]:
    """(rule id, severity, violations) per rule, (rule id, object type, object name) per object, inconclusive rules."""
    root = ET.parse(path).getroot()
    rules: dict[str, tuple[str, int]] = {}
    for test in root.iterfind(".//t:UnitTest", NS):
        props = {p.findtext("t:Key", "", NS): p.findtext("t:Value", "", NS) for p in test.iterfind(".//t:Property", NS)}
        rules[test.get("id", "")] = (props.get("RuleID", ""), int(props.get("Severity", "0") or 0))
    counts: dict[str, int] = {}
    objects: list[tuple[str, str, str]] = []
    inconclusive: list[str] = []
    for result in root.iterfind(".//t:UnitTestResult", NS):
        rule_id, _severity = rules[result.get("testId", "")]
        outcome = result.get("outcome", "")
        counts.setdefault(rule_id, 0)
        if outcome == "Inconclusive":
            inconclusive.append(rule_id)
        if outcome != "Failed":
            continue
        trace = result.findtext(".//t:StackTrace", "", NS)
        for line in trace.splitlines():
            m = OBJECT_LINE.match(line)
            if m:
                objects.append((rule_id, m.group(2), m.group(1)))
        counts[rule_id] = sum(1 for o in objects if o[0] == rule_id)
    rows = sorted((rule_id, sev, counts.get(rule_id, 0)) for rule_id, sev in rules.values())
    return rows, sorted(objects), sorted(inconclusive)


def render(header: list[str], rows) -> str:
    out = [",".join(header)]
    import io

    for r in rows:
        buf = io.StringIO()
        csv.writer(buf, lineterminator="").writerow(r)
        out.append(buf.getvalue())
    return "\n".join(out) + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--trx", required=True, type=Path)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", type=Path, metavar="DIR")
    mode.add_argument("--check", type=Path, metavar="DIR")
    args = ap.parse_args(argv)

    counts, objects, inconclusive = read_trx(args.trx)
    if inconclusive:
        print("rules Tabular Editor could not evaluate: " + ", ".join(inconclusive), file=sys.stderr)
        return 2
    files = {
        COUNTS: render(["rule_id", "severity", "violations"], counts),
        VIOLATIONS: render(["rule_id", "object_type", "object_name"], objects),
    }
    if args.write:
        args.write.mkdir(parents=True, exist_ok=True)
        for name, text in files.items():
            (args.write / name).write_bytes(text.encode("utf-8"))
        print(f"wrote {len(counts)} rules and {len(objects)} violations to {args.write}")
        return 0

    bad = 0
    for name, text in files.items():
        path = args.check / name
        have = path.read_bytes().decode("utf-8").replace("\r\n", "\n") if path.is_file() else ""
        if have != text:
            bad += 1
            old, new = set(have.splitlines()), set(text.splitlines())
            print(f"{name} differs from this run:")
            for line in sorted(new - old):
                print(f"  + (run) {line}")
            for line in sorted(old - new):
                print(f"  - (committed) {line}")
    if bad:
        print("Run tools/summarise_bpa.py --write evidence/bpa after a reviewed change and commit the files.", file=sys.stderr)
        return 1
    print(f"the run matches {args.check}: {len(counts)} rules, {len(objects)} violations")
    return 0


if __name__ == "__main__":
    sys.exit(main())
