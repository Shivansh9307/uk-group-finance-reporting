"""Turn the log of a full-scope build and the output of the test run into small committed evidence files.

The same two logs always give the same files: the parser reads only the lines `ukfr build` prints for its steps and
the summary line `pytest -q` prints last, and the writer sorts nothing (the order is the log's). A local path, a user
or machine name in the input is a stop, because these files are committed.

    uv run --project pipeline ukfr build --scope full --recreate --yes | tee build.log
    UKFR_REQUIRE_DB=1 uv run --project pipeline pytest -q | tee pytest.log
    uv run --project pipeline ukfr build-summary --build-log build.log --pytest-log pytest.log

writes `evidence/full/build_summary.csv` (seconds per step, rows loaded per stage), `evidence/full/pytest_summary.csv`
and `evidence/full/table_counts.csv` (the row count of every table of the full-scope database, a copy of the audit
export the build wrote to `evidence/build/table_counts.csv`).
"""

from __future__ import annotations

import ast
import csv
import io
import re
from pathlib import Path

STEP = re.compile(r"^(database|pre sql|post sql|audit export|stage [A-Za-z0-9_]+): ([0-9.]+) s$")
STAGE_COUNTS = re.compile(r"^  ([A-Za-z0-9_]+): (\{.*\})$")
SCOPE = re.compile(r"^build scope=(\w+)")
PYTEST_LAST = re.compile(r"^(?:=+ )?((?:\d+ \w+(?:, )?)+)(?: \(.*?\))? in ([0-9.]+)s")
PYTEST_PART = re.compile(r"(\d+) (\w+)")
FORBIDDEN = (re.compile(r"[A-Za-z]:\\"), re.compile(r"/Users/"), re.compile(r"/home/"), re.compile(r"Shivansh", re.I))


class SummaryError(ValueError):
    pass


def _check_clean(text: str, what: str) -> None:
    for pattern in FORBIDDEN:
        m = pattern.search(text)
        if m:
            raise SummaryError(f"{what} contains a local path or a name ({m.group(0)!r}); not committing it")


def parse_build_log(text: str) -> tuple[str, list[tuple[str, str, str, str]]]:
    """(scope, rows of item, name, value, unit): a step is `step`, a row count is `rows`, the total is `total`."""
    scope = ""
    rows: list[tuple[str, str, str, str]] = []
    total = 0.0
    for line in text.splitlines():
        line = line.rstrip()
        m = SCOPE.match(line)
        if m:
            scope = m.group(1)
            continue
        m = STEP.match(line)
        if m:
            rows.append(("step", m.group(1), m.group(2), "s"))
            total += float(m.group(2))
            continue
        m = STAGE_COUNTS.match(line)
        if m:
            for key, value in ast.literal_eval(m.group(2)).items():
                rows.append(("rows", f"{m.group(1)}.{key}", str(value), "rows"))
    if not scope or not any(r[0] == "step" for r in rows):
        raise SummaryError("the build log has no 'build scope=' line or no timed step")
    rows.append(("total", "sum of the timed steps", f"{total:.1f}", "s"))
    return scope, rows


def parse_pytest_log(text: str) -> dict[str, str]:
    """Counts and duration from the last summary line of `pytest -q`."""
    for line in reversed(text.splitlines()):
        m = PYTEST_LAST.match(line.strip())
        if m:
            counts = {name: int(n) for n, name in PYTEST_PART.findall(m.group(1))}
            return {
                "passed": str(counts.get("passed", 0)),
                "failed": str(counts.get("failed", 0)),
                "errors": str(counts.get("error", 0) + counts.get("errors", 0)),
                "skipped": str(counts.get("skipped", 0)),
                "duration_s": m.group(2),
            }
    raise SummaryError("no pytest summary line ('N passed ... in X s') found")


def _csv_text(header: list[str], rows: list[list[str]]) -> str:
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(header)
    w.writerows(rows)
    return buf.getvalue()


def write_all(
    build_log: Path, pytest_log: Path, out_dir: Path, table_counts: Path | None, require_clean: bool
) -> list[Path]:
    build_text = build_log.read_text(encoding="utf-8", errors="replace")
    pytest_text = pytest_log.read_text(encoding="utf-8", errors="replace")
    scope, rows = parse_build_log(build_text)
    results = parse_pytest_log(pytest_text)
    if require_clean and (results["skipped"] != "0" or results["failed"] != "0" or results["errors"] != "0"):
        raise SummaryError(f"the test run is not clean: {results}")
    build_rows = [["scope", "build scope", scope, ""]] + [list(r) for r in rows]
    metrics = [["build scope", scope], ["UKFR_REQUIRE_DB", "1"]]
    metrics += [[k, results[k]] for k in ("passed", "failed", "errors", "skipped", "duration_s")]
    files = {
        "build_summary.csv": _csv_text(["kind", "name", "value", "unit"], build_rows),
        "pytest_summary.csv": _csv_text(["metric", "value"], metrics),
    }
    if table_counts is not None:
        files["table_counts.csv"] = table_counts.read_text(encoding="utf-8").replace("\r\n", "\n")
    for name, text in files.items():
        _check_clean(text, name)  # nothing is written if any file would carry a path or a name
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for name, text in files.items():
        path = out_dir / name
        path.write_text(text, encoding="utf-8", newline="")
        written.append(path)
    return written
