"""Prove that the controls can fail: plant a wrong number in a scratch database and require the tests to catch it.

A green run of the control tests says nothing unless the tests would have been red on a wrong number. This
module takes a database that `ukfr build` has already filled (CI uses the second, throwaway one, never the
database the tests ran against), and for each plant it:

1. reads the original value and changes it by one unit,
2. runs the control tests that must notice, in a separate pytest process, and requires that each of them FAILS,
3. puts the original value back and requires the same tests to pass again.

A plant passes only if the planted error is caught and the restore is clean. The step refuses to run against the
default database `UKGroupFinance`, and it changes no file in the repository. How a broken control looks: the
first run of a plant would show `PASSED` for a test and the command would exit 1 with
`NOT CAUGHT: <test id>`; see docs/reconciliation.md.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from .config import find_repo_root
from .db import DEFAULT_DATABASE, Db, DbSettings


@dataclass(frozen=True)
class Plant:
    name: str
    what: str
    apply: Callable[[Db], Callable[[Db], None]]  # plants the error, returns the function that undoes it
    catching: tuple[str, ...]  # pytest node ids that must fail while the error is planted


def _sql_test(root: Path, prefix: str) -> str:
    matches = sorted((root / "sql" / "tests").glob(f"{prefix}_*.sql"))
    if len(matches) != 1:
        raise RuntimeError(f"expected exactly one sql/tests/{prefix}_*.sql, found {len(matches)}")
    return f"pipeline/tests/test_sql_invariants.py::test_invariant[{matches[0].name}]"


def _wrong_control_total(db: Db) -> Callable[[Db], None]:
    """The expected total of one release's primary file is one thousand pounds off."""
    key = db.query(
        "SELECT TOP (1) release, filename, amount_sum_rounded_4dp FROM raw.oscar_inyear_control_expected "
        "WHERE primary_for_release = 'Y' ORDER BY release, filename"
    )[0]
    release, filename, original = key
    db.execute(
        "UPDATE raw.oscar_inyear_control_expected "
        "SET amount_sum_rounded_4dp = CAST(CAST(amount_sum_rounded_4dp AS decimal(38,4)) + 1 AS varchar(100)) "
        "WHERE release = ? AND filename = ?",
        (release, filename),
    )

    def undo(d: Db) -> None:
        d.execute(
            "UPDATE raw.oscar_inyear_control_expected SET amount_sum_rounded_4dp = ? "
            "WHERE release = ? AND filename = ?",
            (original, release, filename),
        )

    return undo


def _wrong_raw_amount(db: Db) -> Callable[[Db], None]:
    """One source amount of the raw load is one thousand pounds off."""
    file_id, source_row = db.query(
        "SELECT TOP (1) file_id, source_row FROM raw.oscar_inyear ORDER BY file_id, source_row"
    )[0]
    db.execute(
        "UPDATE raw.oscar_inyear SET amount_whole = amount_whole + 1 WHERE file_id = ? AND source_row = ?",
        (file_id, source_row),
    )

    def undo(d: Db) -> None:
        d.execute(
            "UPDATE raw.oscar_inyear SET amount_whole = amount_whole - 1 WHERE file_id = ? AND source_row = ?",
            (file_id, source_row),
        )

    return undo


_FACT_KEY = ("release_key", "organisation_key", "segment_key", "account_key", "control_budget_key", "period_key")


def _wrong_fact_amount(db: Db) -> Callable[[Db], None]:
    """One revision delta of the real outturn fact is one thousand pounds off."""
    cols = ", ".join(_FACT_KEY)
    key = db.query(f"SELECT TOP (1) {cols} FROM dw.fact_outturn ORDER BY {cols}")[0]
    where = " AND ".join(f"{c} = ?" for c in _FACT_KEY)
    n = db.scalar(f"SELECT COUNT_BIG(*) FROM dw.fact_outturn WHERE {where}", tuple(key))
    if n != 1:
        raise RuntimeError(f"the chosen fact row is not unique ({n} rows at grain {key})")
    db.execute(f"UPDATE dw.fact_outturn SET amount_delta = amount_delta + 1 WHERE {where}", tuple(key))

    def undo(d: Db) -> None:
        d.execute(f"UPDATE dw.fact_outturn SET amount_delta = amount_delta - 1 WHERE {where}", tuple(key))

    return undo


def plants(root: Path) -> list[Plant]:
    return [
        Plant(
            "wrong_control_total",
            "the control total of one release is 1 (GBP thousand) too high",
            _wrong_control_total,
            (_sql_test(root, "004"), _sql_test(root, "302")),
        ),
        Plant(
            "wrong_raw_amount",
            "one raw source amount is 1 (GBP thousand) too high",
            _wrong_raw_amount,
            (_sql_test(root, "003"),),
        ),
        Plant(
            "wrong_fact_amount",
            "one revision delta of dw.fact_outturn is 1 (GBP thousand) too high",
            _wrong_fact_amount,
            (
                _sql_test(root, "302"),
                "pipeline/tests/test_real_totals.py::"
                "test_the_real_facts_have_the_row_counts_and_sums_pinned_in_the_expectation_file",
            ),
        ),
    ]


def run_pytest(root: Path, nodes: tuple[str, ...]) -> tuple[int, set[str], str]:
    """Run the given tests in their own process; return the exit code, the node ids that failed and the output."""
    proc = subprocess.run(
        [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", "--no-header", "-rf", *nodes],
        cwd=root,
        capture_output=True,
        text=True,
        env=os.environ.copy(),
    )
    # pytest prints the path of a test file with the separator of the platform; ids here use forward slashes
    failed = {n.replace(chr(92), "/") for n in re.findall(r"^FAILED (\S+)", proc.stdout, flags=re.MULTILINE)}
    return proc.returncode, failed, proc.stdout + proc.stderr


def run(root: Path | None = None, log=print) -> int:
    root = root or find_repo_root()
    settings = DbSettings.from_env()
    if settings.database.lower() == DEFAULT_DATABASE.lower():
        log(f"refusing to plant errors in {settings.database}; point UKFR_SQL_DATABASE at a throwaway build")
        return 2
    os.environ["UKFR_REQUIRE_DB"] = "1"
    ok = True
    log(f"negative control on {settings.describe()}")
    for plant in plants(root):
        log(f"- {plant.name}: {plant.what}")
        with Db(settings) as db:
            undo = plant.apply(db)
            try:
                code, failed, out = run_pytest(root, plant.catching)
            finally:
                undo(db)
        for node in plant.catching:
            caught = node in failed
            log(f"    {'caught' if caught else 'NOT CAUGHT'}: {node}")
            ok &= caught
        if code != 1:
            log(f"    expected pytest exit code 1 with the error planted, got {code}")
            ok = False
            log(out[-2000:])
        code, failed, out = run_pytest(root, plant.catching)
        log(f"    after the restore: pytest exit code {code} ({'clean' if code == 0 else 'STILL FAILING'})")
        if code != 0:
            ok = False
            log(out[-2000:])
    log(
        "negative control: every planted error was caught and every restore is clean"
        if ok
        else "negative control FAILED"
    )
    return 0 if ok else 1
