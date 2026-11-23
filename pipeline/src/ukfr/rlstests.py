"""Role cases for the model's row-level and object-level security: expected values from the warehouse, results from
the model under a role and a user, a comparison.

Layout, from the repository root:

    tests/rls/manifest.csv                 one row per case: case, query, role, user, mode, expected, expect_error
    tests/rls/queries/<query>.dax          the DAX the case runs (an EVALUATE, shared by many cases)
    tests/rls/expected/<expected>.sql      an independent query over dw and synthetic tables; `{user}` becomes the
                                           case's user, written as an N'...' literal
    tests/rls/expected/<query>__<case>.csv written by `ukfr rls-expected`
    tests/rls/results/<query>__<case>.csv  written by tools/run_rls_tests.ps1 (run through tools/run_dax.ps1 with -Roles
                                           and -User); a query the engine refuses is written as `outcome,message`
    evidence/model/rls_tests.csv           written by `ukfr rls-compare`

Modes of a case:

    values   the result equals the expected values (same comparison as the DAX tests: rows in any order, numbers to
             0.0001, text exact)
    differs  the result is NOT equal to the expected values: used with the unfiltered total, to show that a role never
             sees the full total
    error    the engine refuses the query and its message contains `expect_error` (object-level security)

Users are always passed to the engine with ActAs, never by the identity of whoever runs the tool: on this machine
USERPRINCIPALNAME() would otherwise be MACHINE\\user and match no row.
"""

from __future__ import annotations

import csv
import re
from dataclasses import dataclass
from pathlib import Path

from . import modeltests

RLS_DIR = Path("tests") / "rls"
MANIFEST = RLS_DIR / "manifest.csv"
QUERIES_DIR = RLS_DIR / "queries"
EXPECTED_DIR = RLS_DIR / "expected"
RESULTS_DIR = RLS_DIR / "results"
EVIDENCE_CSV = Path("evidence") / "model" / "rls_tests.csv"
MODEL_ROLES_DIR = Path("model") / "UKGroupFinance.SemanticModel" / "definition" / "roles"
MODES = ("values", "differs", "error")
MANIFEST_HEADER = ["case", "query", "role", "user", "mode", "expected", "expect_error"]
EVIDENCE_HEADER = [
    "case",
    "query",
    "role",
    "user",
    "mode",
    "expected_rows",
    "result_rows",
    "status",
    "max_abs_diff",
]
_USER = re.compile(r"^[A-Za-z0-9._-]+@example\.org$", re.IGNORECASE)
_NAME = re.compile(r"^[a-z0-9]+(?:_[a-z0-9]+)*$")


class RlsTestError(RuntimeError):
    """A problem with the case files themselves (not a failing comparison)."""


@dataclass(frozen=True)
class Case:
    case: str
    query: str
    role: str
    user: str
    mode: str
    expected: str
    expect_error: str

    @property
    def stem(self) -> str:
        return f"{self.query}__{self.case}"


def read_manifest(root: Path) -> list[Case]:
    path = root / MANIFEST
    if not path.is_file():
        raise RlsTestError(f"{MANIFEST.as_posix()} does not exist")
    with path.open(encoding="utf-8-sig", newline="") as fh:
        reader = csv.DictReader(fh)
        if reader.fieldnames != MANIFEST_HEADER:
            raise RlsTestError(f"{MANIFEST.as_posix()}: the header must be {','.join(MANIFEST_HEADER)}")
        return [Case(**{k: (r[k] or "").strip() for k in MANIFEST_HEADER}) for r in reader]


def check_manifest(root: Path, cases: list[Case] | None = None) -> list[str]:
    """Problems with the case files (empty when the manifest, the queries and the expected sources agree)."""
    cases = cases if cases is not None else read_manifest(root)
    problems = []
    roles = {p.stem for p in (root / MODEL_ROLES_DIR).glob("*.tmdl")}
    seen: set[str] = set()
    for c in cases:
        if not _NAME.match(c.case):
            problems.append(f"case {c.case!r}: lower case words joined by underscores")
        if c.stem in seen:
            problems.append(f"case {c.stem}: used twice")
        seen.add(c.stem)
        if not (root / QUERIES_DIR / f"{c.query}.dax").is_file():
            problems.append(f"case {c.case}: no tests/rls/queries/{c.query}.dax")
        if c.role not in roles:
            problems.append(f"case {c.case}: role {c.role!r} is not a role of the model ({sorted(roles)})")
        if not _USER.match(c.user):
            problems.append(f"case {c.case}: user {c.user!r} must be an address at example.org")
        if c.mode not in MODES:
            problems.append(f"case {c.case}: mode {c.mode!r} is not one of {MODES}")
        elif c.mode == "error" and not c.expect_error:
            problems.append(f"case {c.case}: an error case needs expect_error")
        elif c.mode != "error" and not (root / EXPECTED_DIR / f"{c.expected}.sql").is_file():
            problems.append(f"case {c.case}: no tests/rls/expected/{c.expected}.sql")
    return problems


def user_literal(user: str) -> str:
    if not _USER.match(user):
        raise RlsTestError(f"user {user!r} must be an address at example.org")
    return "N'" + user + "'"


def expected_sql(root: Path, case: Case) -> str:
    text = (root / EXPECTED_DIR / f"{case.expected}.sql").read_text(encoding="utf-8")
    return text.replace("{user}", user_literal(case.user))


def write_expected(root: Path, db, pattern: str = "") -> list[tuple[str, int]]:
    """Run the expected source of every values or differs case whose stem contains `pattern`; write its CSV."""
    cases = read_manifest(root)
    problems = check_manifest(root, cases)
    if problems:
        raise RlsTestError("; ".join(problems))
    done = []
    for c in cases:
        if c.mode == "error" or (pattern and pattern not in c.stem):
            continue
        names, rows = db.columns(expected_sql(root, c))
        if not names or len(set(names)) != len(names):
            raise RlsTestError(f"{c.expected}.sql: column names must be unique and named")
        cells = [[modeltests.format_cell(v) for v in r] for r in rows]
        modeltests.write_csv(root / EXPECTED_DIR / f"{c.stem}.csv", names, cells)
        done.append((c.stem, len(rows)))
    return done


@dataclass
class Result:
    case: Case
    status: str = "pass"
    expected_rows: int | str = ""
    result_rows: int | str = ""
    max_abs_diff: str = ""
    details: tuple[str, ...] = ()

    @property
    def ok(self) -> bool:
        return self.status == "pass"


def _read_result(path: Path) -> tuple[list[str], list[list[str]]]:
    """Header and rows of a result file; a file with only a header is a result with no rows."""
    return modeltests.read_csv(path)


def compare_case(root: Path, c: Case) -> Result:
    res = Result(c)
    result_path = root / RESULTS_DIR / f"{c.stem}.csv"
    if not result_path.is_file():
        res.status, res.details = "missing_result", (f"no {result_path.name}: run tools/run_rls_tests.ps1",)
        return res
    result = _read_result(result_path)
    res.result_rows = len(result[1])
    if c.mode == "error":
        header, rows = result
        if [h.casefold() for h in header] != ["outcome", "message"] or not rows:
            res.status = "fail"
            res.details = ("the query was not refused: the engine returned a result",)
            return res
        outcome, message = rows[0][0], rows[0][1]
        if outcome != "error" or c.expect_error.casefold() not in message.casefold():
            res.status = "fail"
            res.details = (f"expected an error containing {c.expect_error!r}, got {outcome}: {message!r}",)
        return res
    expected_path = root / EXPECTED_DIR / f"{c.stem}.csv"
    if not expected_path.is_file():
        res.status, res.details = "missing_expected", (f"no {expected_path.name}: run `ukfr rls-expected`",)
        return res
    expected = modeltests.read_csv(expected_path)
    res.expected_rows = len(expected[1])
    if [h.casefold() for h in result[0]] == ["outcome", "message"] and [h.casefold() for h in expected[0]] != [
        "outcome",
        "message",
    ]:
        res.status = "fail"
        res.details = (f"the engine refused the query: {result[1][0][1] if result[1] else ''}",)
        return res
    out = modeltests.compare_tables(expected, result)
    res.max_abs_diff = out.max_abs_diff
    if c.mode == "values":
        res.status, res.details = out.status, tuple(out.details)
    else:  # differs
        if out.status == "pass":
            res.status = "fail"
            res.details = ("the result equals the unfiltered total: the role sees everything",)
        else:
            res.status, res.details = "pass", ()
    return res


def compare_all(root: Path) -> list[Result]:
    cases = read_manifest(root)
    return [compare_case(root, c) for c in cases]


def write_evidence(path: Path, results: list[Result]) -> None:
    rows = [
        [
            r.case.stem,
            r.case.query,
            r.case.role,
            r.case.user,
            r.case.mode,
            r.expected_rows,
            r.result_rows,
            r.status,
            r.max_abs_diff,
        ]
        for r in results
    ]
    modeltests.write_csv_plain(path, EVIDENCE_HEADER, rows)
