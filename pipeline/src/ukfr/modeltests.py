"""The DAX test framework: expected values from the warehouse, results from the model, a comparison.

Layout, from the repository root:

    tests/dax/<NNN>_<name>.dax          one EVALUATE query run against the model open in Desktop
    tests/expected/<NNN>_<name>.sql     an independent query over dw base tables (never over dw.v_model_*)
    tests/expected/<NNN>_<name>.py      or, where the truth is not in the warehouse (the web-read deflators), a
                                        module with `generate(root) -> (columns, rows)`
    tests/expected/<NNN>_<name>.csv     written by `ukfr expected`
    tests/expected/_meta.csv            the build scope the expected files were written from
    tests/results/<NNN>_<name>.csv      written by tools/run_dax_tests.ps1 from the DAX query
    evidence/model/dax_tests.csv        written by `ukfr dax-compare`

`ukfr expected` writes the expected files; `ukfr dax-compare` compares them with the results. The comparison is
by column and does not depend on the order of rows: both sides are sorted on all columns, left to right, before they
are compared, so put identifying columns before measures. Numbers are compared with an absolute tolerance of
0.0001, the resolution of DECIMAL(19,4) (the model holds amounts as fixed decimals with four places), so the
tolerance never hides a difference in the data; text, dates and booleans must match exactly.
"""

from __future__ import annotations

import csv
import importlib.util
import re
from dataclasses import dataclass, field
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any

DAX_DIR = Path("tests") / "dax"
EXPECTED_DIR = Path("tests") / "expected"
RESULTS_DIR = Path("tests") / "results"
EVIDENCE_CSV = Path("evidence") / "model" / "dax_tests.csv"
META_FILE = "_meta.csv"
TOLERANCE = Decimal("0.0001")
ID_RE = re.compile(r"^(\d{3})_([a-z0-9]+(?:_[a-z0-9]+)*)$")
_NUMBER = re.compile(r"^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$")
EVIDENCE_HEADER = [
    "test_id",
    "test_name",
    "expected_rows",
    "result_rows",
    "columns",
    "status",
    "max_abs_diff",
    "build_scope",
]


class ModelTestError(RuntimeError):
    """A problem with the test files themselves (not a failing comparison)."""


# --------------------------------------------------------------------------------------------- discovery
def dax_tests(root: Path, dax_dir: Path | None = None) -> list[Path]:
    return sorted((dax_dir or root / DAX_DIR).glob("*.dax"))


def expected_sources(root: Path, expected_dir: Path | None = None) -> dict[str, Path]:
    """Test stem -> the .sql or .py that produces its expected values."""
    out: dict[str, Path] = {}
    for p in sorted((expected_dir or root / EXPECTED_DIR).iterdir()):
        if p.suffix in (".sql", ".py") and ID_RE.match(p.stem):
            if p.stem in out:
                raise ModelTestError(f"{p.stem} has both a .sql and a .py expected source")
            out[p.stem] = p
    return out


def check_pairs(root: Path) -> list[str]:
    """Problems with the pairing of tests and expected sources (empty when every .dax has one source and back)."""
    problems = []
    dax = {p.stem: p for p in dax_tests(root)}
    exp = expected_sources(root)
    for stem in dax:
        if not ID_RE.match(stem):
            problems.append(f"{stem}.dax: the name must be <three digits>_<lower_case_words>")
        if stem not in exp:
            problems.append(f"{stem}.dax has no tests/expected/{stem}.sql (or .py)")
    for stem in exp:
        if stem not in dax:
            problems.append(f"tests/expected/{exp[stem].name} has no tests/dax/{stem}.dax")
    ids = [s[:3] for s in dax]
    for i in sorted({i for i in ids if ids.count(i) > 1}):
        problems.append(f"test number {i} is used by more than one .dax file")
    return problems


# ------------------------------------------------------------------------------------------ cell formatting
def format_cell(v: Any) -> str:
    """The canonical text of one value of an expected result."""
    if v is None:
        return ""
    if isinstance(v, bool):
        return "True" if v else "False"
    if isinstance(v, Decimal):
        return format(v, "f")
    if isinstance(v, datetime):
        return v.strftime("%Y-%m-%d") if v.time() == datetime.min.time() else v.isoformat(sep=" ")
    if isinstance(v, date):
        return v.isoformat()
    if isinstance(v, float):
        raise ModelTestError("a float in an expected result: cast it to DECIMAL in the query")
    return str(v)


def sort_key(row: list[str]) -> tuple:
    """Sort on all columns, numbers by value and text case-insensitively, blanks first."""
    key = []
    for c in row:
        if c == "":
            key.append((0, Decimal(0), ""))
        elif _NUMBER.match(c):
            try:
                key.append((1, Decimal(c), ""))
                continue
            except InvalidOperation:
                key.append((2, Decimal(0), c.casefold()))
        else:
            key.append((2, Decimal(0), c.casefold()))
    return tuple(key)


def write_csv(path: Path, header: list[str], rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(header)
        w.writerows(sorted(rows, key=sort_key))


def read_csv(path: Path) -> tuple[list[str], list[list[str]]]:
    with path.open(encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.reader(fh))
    if not rows:
        raise ModelTestError(f"{path.name} is empty")
    return [normalise_header(h) for h in rows[0]], [[c.strip() for c in r] for r in rows[1:]]


def normalise_header(h: str) -> str:
    """dscmd writes a column as [name] or Table[name]; the tests name their columns, so keep the bare name."""
    h = h.strip()
    m = re.match(r"^(?:.*)?\[(.+)\]$", h)
    return (m.group(1) if m else h).strip()


# ------------------------------------------------------------------------------------------------ expected
def _generate_py(root: Path, path: Path) -> tuple[list[str], list[list[str]]]:
    spec = importlib.util.spec_from_file_location(f"ukfr_expected_{path.stem}", path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    columns, rows = mod.generate(root)
    return list(columns), [[format_cell(c) if not isinstance(c, str) else c for c in r] for r in rows]


def generate_one(root: Path, db, path: Path) -> tuple[list[str], list[list[str]]]:
    if path.suffix == ".py":
        return _generate_py(root, path)
    names, rows = db.columns(path.read_text(encoding="utf-8"))
    return names, [[format_cell(c) for c in r] for r in rows]


def write_expected(root: Path, db, scope: str, pattern: str = "", out_dir: Path | None = None) -> list[tuple[str, int]]:
    """Run every expected source whose stem contains `pattern` and write its CSV. Returns (stem, rows)."""
    problems = check_pairs(root)
    if problems:
        raise ModelTestError("; ".join(problems))
    out_dir = out_dir or root / EXPECTED_DIR
    done = []
    for stem, src in expected_sources(root).items():
        if pattern and pattern not in stem:
            continue
        header, rows = generate_one(root, db, src)
        if not header or len(set(header)) != len(header):
            raise ModelTestError(f"{src.name}: column names must be unique and named")
        write_csv(out_dir / f"{stem}.csv", header, rows)
        done.append((stem, len(rows)))
    if not pattern:  # the scope belongs to the whole set; a filtered run leaves it as it was
        write_csv_plain(out_dir / META_FILE, ["key", "value"], [["build_scope", scope]])
    return done


def write_csv_plain(path: Path, header: list[str], rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)


def read_scope(expected_dir: Path) -> str:
    p = expected_dir / META_FILE
    if not p.is_file():
        return ""
    with p.open(encoding="utf-8", newline="") as fh:
        for r in csv.DictReader(fh):
            if r["key"] == "build_scope":
                return r["value"]
    return ""


# ------------------------------------------------------------------------------------------------ compare
@dataclass
class Outcome:
    stem: str
    expected_rows: int | str = ""
    result_rows: int | str = ""
    columns: int | str = ""
    status: str = "pass"
    max_abs_diff: str = ""
    details: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return self.status == "pass"


def _num(c: str) -> Decimal | None:
    if c and _NUMBER.match(c):
        try:
            return Decimal(c)
        except InvalidOperation:
            return None
    return None


def _same_text(a: str, b: str) -> bool:
    """Booleans may be written True/False or true/false; everything else is compared as written."""
    if a == b:
        return True
    return a.lower() in ("true", "false") and a.lower() == b.lower()


def compare_tables(
    expected: tuple[list[str], list[list[str]]],
    result: tuple[list[str], list[list[str]]],
    tolerance: Decimal = TOLERANCE,
) -> Outcome:
    eh, er = expected
    rh, rr = result
    out = Outcome("", len(er), len(rr), len(eh))
    if [h.casefold() for h in eh] != [h.casefold() for h in rh]:
        out.status = "fail"
        out.details.append(f"columns differ: expected {eh}, result {rh}")
        return out
    if len(er) != len(rr):
        out.status = "fail"
        out.details.append(f"row count differs: expected {len(er)}, result {len(rr)}")
        return out
    worst = Decimal(0)
    seen_number = False
    bad = 0
    for e_row, r_row in zip(sorted(er, key=sort_key), sorted(rr, key=sort_key), strict=True):
        if len(e_row) != len(eh) or len(r_row) != len(rh):
            out.status = "fail"
            out.details.append("a row has the wrong number of columns")
            return out
        for name, e, r in zip(eh, e_row, r_row, strict=True):
            en, rn = _num(e), _num(r)
            if en is not None and rn is not None:
                seen_number = True
                d = abs(en - rn)
                worst = max(worst, d)
                if d > tolerance:
                    bad += 1
                    if bad <= 5:
                        out.details.append(f"{name}: expected {e}, result {r} (difference {d})")
            elif not _same_text(e, r):
                bad += 1
                if bad <= 5:
                    out.details.append(f"{name}: expected {e!r}, result {r!r}")
    if seen_number:
        out.max_abs_diff = format(worst, "f")
    if bad:
        out.status = "fail"
        out.details.append(f"{bad} differing cell(s)")
    return out


def compare_all(
    root: Path,
    expected_dir: Path | None = None,
    results_dir: Path | None = None,
    dax_dir: Path | None = None,
) -> list[Outcome]:
    expected_dir = expected_dir or root / EXPECTED_DIR
    results_dir = results_dir or root / RESULTS_DIR
    outcomes = []
    for dax in dax_tests(root, dax_dir):
        stem = dax.stem
        e_path, r_path = expected_dir / f"{stem}.csv", results_dir / f"{stem}.csv"
        if not e_path.is_file():
            outcomes.append(
                Outcome(stem, status="missing_expected", details=[f"no {e_path.name}: run `ukfr expected`"])
            )
            continue
        if not r_path.is_file():
            outcomes.append(
                Outcome(stem, status="missing_result", details=[f"no {r_path.name}: run tools/run_dax_tests.ps1"])
            )
            continue
        o = compare_tables(read_csv(e_path), read_csv(r_path))
        o.stem = stem
        outcomes.append(o)
    return outcomes


def write_evidence(path: Path, outcomes: list[Outcome], scope: str) -> None:
    rows = []
    for o in outcomes:
        tid, _, name = o.stem.partition("_")
        rows.append([tid, name, o.expected_rows, o.result_rows, o.columns, o.status, o.max_abs_diff, scope])
    write_csv_plain(path, EVIDENCE_HEADER, rows)
