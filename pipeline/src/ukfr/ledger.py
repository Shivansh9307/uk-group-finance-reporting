"""The evidence ledger: which model the committed test evidence belongs to, and a check that nothing has drifted.

The DAX tests and the role cases run in Power BI Desktop, which a hosted runner does not have. So CI cannot run them
again. What it can do is make the evidence tamper-evident: `evidence/ledger.json` records

  - a hash of the semantic model's TMDL files, taken as a projection that leaves out what Desktop and Tabular Editor
    rewrite on every save (lineage tags, change markers, tool annotations, the order of objects, the names of
    relationships) and keeps everything that means something (names, expressions, data types, descriptions, format
    strings, display folders, calculation items, roles, perspectives, relationships);
  - the sha256 of every DAX test, expected file and result file, of the role cases (queries, expected values, results),
    of the committed-scope set of expected values, and of the model reference;
  - the build scope each set of expected values came from;
  - the model hash that `docs/model-reference.md` was generated from.

`ukfr ledger write` refuses to write unless the DAX comparison and the role-case comparison pass on the files on disk
and the model reference was generated from the model as it is now. `ukfr ledger check` recomputes everything and fails
on any changed, missing or extra file, on a model that no longer matches its ledger, and on a stale model reference.

This is a ledger and not a rerun. A matching ledger says that the model, the queries, the expected values and the
results are the ones that were compared and passed together on my machine. It does not prove that the results were
produced by that model: nothing in CI can. See docs/evidence.md.

The module reads only the standard library apart from `modeltests` and `rlstests` (also standard library only), so
`PYTHONPATH=pipeline/src python3 -m ukfr.ledger check` runs on a bare runner.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

LEDGER = Path("evidence") / "ledger.json"
MODEL_DEFINITION = Path("model") / "UKGroupFinance.SemanticModel" / "definition"
REFERENCE = Path("docs") / "model-reference.md"
REFERENCE_QUERIES = Path("tools") / "model_reference"
REFERENCE_CSVS = Path("evidence") / "model" / "reference"
LEDGER_VERSION = 1

# Sets of expected values and the scope each was written at (tests/<dir>/_meta.csv).
EXPECTED_SETS = ("tests/expected", "tests/expected_committed")

# Directories whose every file is in the ledger (an extra file there is a failure), and single files.
TRACKED_DIRS = (
    "tests/dax",
    "tests/expected",
    "tests/expected_committed",
    "tests/results",
    "tests/rls",
    "tools/model_reference",
    "evidence/model/reference",
)
TRACKED_FILES = ("evidence/model/dax_tests.csv", "evidence/model/rls_tests.csv")

PROJECTION_LINE = re.compile(r"^Model projection hash: `([0-9a-f]{64})`\s*$", re.MULTILINE)


class LedgerError(RuntimeError):
    """The ledger cannot be written or read (not a failing check)."""


# ------------------------------------------------------------------------------------------ file hashes
def normalised_sha256(path: Path) -> str:
    """sha256 of a file's bytes with CRLF turned into LF, so autocrlf does not change a hash."""
    data = path.read_bytes().replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()


def kind_of(rel: str) -> str:
    """What a tracked file is, from its path: the counts of the ledger are by this."""
    name = rel.rsplit("/", 1)[-1]
    suffix = name.rsplit(".", 1)[-1] if "." in name else ""
    if rel.startswith("tests/dax/"):
        return "dax_test"
    if rel.startswith("tests/expected_committed/"):
        return "expected_committed"
    if rel.startswith("tests/expected/"):
        return "expected_value" if suffix == "csv" else "expected_source"
    if rel.startswith("tests/results/"):
        return "dax_result"
    if rel.startswith("tests/rls/results/"):
        return "rls_result"
    if rel.startswith("tests/rls/expected/"):
        return "rls_expected_value" if suffix == "csv" else "rls_expected_source"
    if rel.startswith("tests/rls/queries/"):
        return "rls_query"
    if rel.startswith("tests/rls/"):
        return "rls_manifest"
    if rel.startswith("tools/model_reference/"):
        return "model_reference_query"
    if rel.startswith("evidence/model/reference/"):
        return "model_reference_input"
    return "comparison"


def tracked_files(root: Path) -> list[str]:
    """Repository-relative posix paths of every file the ledger covers, sorted."""
    found: set[str] = set()
    for d in TRACKED_DIRS:
        base = root / d
        if base.is_dir():
            for p in base.rglob("*"):
                if p.is_file() and "__pycache__" not in p.parts:  # Python writes these when an expected source runs
                    found.add(p.relative_to(root).as_posix())
    for f in TRACKED_FILES:
        if (root / f).is_file():
            found.add(f)
    return sorted(found)


def file_hashes(root: Path) -> dict[str, str]:
    return {rel: normalised_sha256(root / rel) for rel in tracked_files(root)}


def expected_scopes(root: Path) -> dict[str, str]:
    """The build scope written in each set of expected values ('' when the set has none)."""
    from . import modeltests

    return {d: modeltests.read_scope(root / d) for d in EXPECTED_SETS}


# ------------------------------------------------------------------------------------- model projection
_QUOTED_IDENT = re.compile(r"'([A-Za-z_][A-Za-z0-9_]*)'")
_ANNOTATION_NAME = re.compile(r"^annotation\s+(?:'((?:[^']|'')+)'|([^\s=]+))")
# Annotations Desktop and Tabular Editor write for their own use. __PBI_TimeIntelligenceEnabled changes what the engine
# does (automatic date tables), so it is kept.
_VOLATILE_ANNOTATION = re.compile(r"^(?:PBI_|__PBI_(?!TimeIntelligenceEnabled$)|__TEdtr$)")
_VOLATILE_LINE = re.compile(r"^(?:lineageTag|sourceLineageTag)\s*:|^changedProperty\s*=")


@dataclass
class _Node:
    header: str
    depth: int
    docs: list[str] = field(default_factory=list)
    body: list[str] = field(default_factory=list)
    children: list[_Node] = field(default_factory=list)


def _normalise_header(text: str) -> str:
    text = text.rstrip()
    if text.startswith("relationship "):
        return "relationship"  # the name is a generated id; what the relationship joins is in its properties
    return _QUOTED_IDENT.sub(r"\1", text)


def _is_volatile(header: str) -> bool:
    if _VOLATILE_LINE.match(header):
        return True
    m = _ANNOTATION_NAME.match(header)
    return bool(m and _VOLATILE_ANNOTATION.match(m.group(1) or m.group(2)))


def _parse_tmdl(text: str) -> _Node:
    """Indentation tree of a TMDL file. A line two or more tabs below a node and before its first property is the
    node's expression, and a line below a property is that property's expression: both stay in order as a body."""
    root = _Node("", -1)
    stack = [root]
    pending_docs: list[str] = []
    fence_owner: _Node | None = None
    for raw in re.split(r"\r\n|\r|\n", text.lstrip("﻿")):
        if fence_owner is not None:  # inside a ``` block: verbatim until the closing fence
            fence_owner.body.append(raw.strip("\t").rstrip())
            if raw.strip().startswith("```"):
                fence_owner = None
            continue
        if not raw.strip():
            continue
        line = raw.rstrip()
        depth = len(line) - len(line.lstrip("\t"))
        content = line.lstrip("\t")
        if content.startswith("///"):
            pending_docs.append(content)
            continue
        while stack[-1].depth >= depth:
            stack.pop()
        parent = stack[-1]
        if depth == parent.depth + 1:
            node = _Node(_normalise_header(content), depth, docs=pending_docs)
            pending_docs = []
            parent.children.append(node)
            stack.append(node)
            if content.endswith("```"):
                fence_owner = node
        else:
            parent.body.append(content)
    root.docs = pending_docs
    return root


def _drop_volatile(node: _Node) -> None:
    node.children = [c for c in node.children if not _is_volatile(c.header)]
    for c in node.children:
        _drop_volatile(c)


def _render(node: _Node) -> str:
    pad = "\t" * node.depth
    lines = [pad + d for d in node.docs] + [pad + node.header] + ["\t" * (node.depth + 2) + b for b in node.body]
    return "\n".join(lines + sorted(_render(c) for c in node.children))


def canonical_tmdl(text: str) -> str:
    """One TMDL file in its canonical form: no volatile metadata, objects in sorted order, expressions as written."""
    root = _parse_tmdl(text)
    _drop_volatile(root)
    parts = [d for d in root.docs] + sorted(_render(c) for c in root.children)
    return "\n".join(parts) + "\n"


def model_files(root: Path, definition: Path | None = None) -> list[Path]:
    base = definition or root / MODEL_DEFINITION
    return sorted(base.rglob("*.tmdl"), key=lambda p: p.relative_to(base).as_posix().casefold())


def projection(root: Path, definition: Path | None = None) -> str:
    """The canonical text of the whole model definition (every .tmdl file under `definition`)."""
    base = definition or root / MODEL_DEFINITION
    if not base.is_dir():
        raise LedgerError(f"{base.as_posix()} does not exist")
    parts = []
    for p in model_files(root, base):
        rel = p.relative_to(base).as_posix()
        parts.append(f"=== {rel}\n{canonical_tmdl(p.read_text(encoding='utf-8-sig'))}")
    return "".join(parts)


def projection_hash(root: Path, definition: Path | None = None) -> str:
    return hashlib.sha256(projection(root, definition).encode("utf-8")).hexdigest()


# ------------------------------------------------------------------------------------------ the reference
def reference_projection(root: Path) -> str:
    """The model hash that docs/model-reference.md says it was generated from ('' when it says nothing)."""
    path = root / REFERENCE
    if not path.is_file():
        return ""
    m = PROJECTION_LINE.search(path.read_text(encoding="utf-8"))
    return m.group(1) if m else ""


# ---------------------------------------------------------------------------------------------- the ledger
def build(root: Path) -> dict:
    """The ledger of the files as they are now (no gate: `write` applies the gate)."""
    files = file_hashes(root)
    counts: dict[str, int] = {}
    for rel in files:
        counts[kind_of(rel)] = counts.get(kind_of(rel), 0) + 1
    ref = root / REFERENCE
    return {
        "ledger_version": LEDGER_VERSION,
        "model": {
            "projection_sha256": projection_hash(root),
            "tmdl_files": len(model_files(root)),
        },
        "expected_build_scope": expected_scopes(root),
        "model_reference": {
            "path": REFERENCE.as_posix(),
            "sha256": normalised_sha256(ref) if ref.is_file() else "",
            "projection_sha256": reference_projection(root),
        },
        "counts": dict(sorted(counts.items())),
        "files": files,
    }


def gate(root: Path) -> list[str]:
    """Reasons a ledger must not be written now: the comparisons must pass on the files on disk."""
    from . import modeltests, rlstests

    problems: list[str] = []
    problems += _comparison_problems(root, modeltests, rlstests)
    ref = reference_projection(root)
    if not ref:
        problems.append(f"{REFERENCE.as_posix()} does not say which model it was generated from: run `ukfr model-docs`")
    elif ref != projection_hash(root):
        problems.append(f"{REFERENCE.as_posix()} is stale: regenerate in Desktop (`ukfr model-docs`)")
    return problems


def _comparison_problems(root: Path, modeltests, rlstests) -> list[str]:
    problems: list[str] = []
    try:
        pairs = modeltests.check_pairs(root)
        problems += [f"dax tests: {p}" for p in pairs]
        outcomes = modeltests.compare_all(root)
    except modeltests.ModelTestError as exc:
        return [f"dax tests: {exc}"]
    if not outcomes:
        problems.append("dax tests: there are none")
    for o in outcomes:
        if not o.ok:
            problems.append(f"dax test {o.stem}: {o.status} {'; '.join(o.details)}".rstrip())
    scope = modeltests.read_scope(root / "tests" / "expected")
    if scope != "full":
        problems.append(f"tests/expected was written at scope {scope or 'unknown'}, not full")
    try:
        problems += [f"role cases: {p}" for p in rlstests.check_manifest(root)]
        results = rlstests.compare_all(root)
    except rlstests.RlsTestError as exc:
        return problems + [f"role cases: {exc}"]
    if not results:
        problems.append("role cases: there are none")
    for r in results:
        if not r.ok:
            problems.append(f"role case {r.case.stem}: {r.status} {'; '.join(r.details)}".rstrip())
    return problems


def write(root: Path, *, ignore_gate: bool = False) -> dict:
    problems = [] if ignore_gate else gate(root)
    if problems:
        raise LedgerError(
            "the ledger is written only after a Desktop run in which the DAX comparison, the role-case comparison "
            "and the model reference all agree with the model:\n  " + "\n  ".join(problems)
        )
    ledger = build(root)
    path = root / LEDGER
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(ledger, indent=1, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    return ledger


def check(root: Path, *, compare: bool = True) -> list[str]:
    """Everything that disagrees with the ledger (empty when it matches). `compare` also reruns the two comparisons."""
    path = root / LEDGER
    if not path.is_file():
        return [f"{LEDGER.as_posix()} does not exist: run `ukfr ledger write`"]
    try:
        stored = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return [f"{LEDGER.as_posix()} is not valid JSON: {exc}"]
    if stored.get("ledger_version") != LEDGER_VERSION:
        return [f"{LEDGER.as_posix()} has version {stored.get('ledger_version')!r}, this tool reads {LEDGER_VERSION}"]
    now = build(root)
    problems: list[str] = []

    if now["model"]["projection_sha256"] != stored["model"]["projection_sha256"]:
        problems.append(
            "the model changed since the evidence was written: projection hash "
            f"{stored['model']['projection_sha256'][:12]} in the ledger, {now['model']['projection_sha256'][:12]} now. "
            "Run the DAX tests and the role cases in Desktop, regenerate the model reference, then `ukfr ledger write`"
        )
    ref_now, ref_ledger = now["model_reference"], stored["model_reference"]
    if ref_now["projection_sha256"] != now["model"]["projection_sha256"]:
        problems.append(
            f"{REFERENCE.as_posix()} is stale: it was generated from model "
            f"{(ref_now['projection_sha256'] or 'unknown')[:12]}, "
            f"the model is {now['model']['projection_sha256'][:12]}. "
            "Regenerate in Desktop (`ukfr model-docs`)"
        )
    if ref_now["sha256"] != ref_ledger["sha256"]:
        problems.append(f"{REFERENCE.as_posix()} differs from the file the ledger recorded")
    if now["expected_build_scope"] != stored["expected_build_scope"]:
        problems.append(
            f"expected build scope {now['expected_build_scope']} differs from the ledger's "
            f"{stored['expected_build_scope']}"
        )

    have, want = now["files"], stored["files"]
    for rel in sorted(set(want) - set(have)):
        problems.append(f"missing: {rel} is in the ledger and not on disk")
    for rel in sorted(set(have) - set(want)):
        problems.append(f"extra: {rel} is on disk and not in the ledger")
    for rel in sorted(set(have) & set(want)):
        if have[rel] != want[rel]:
            problems.append(f"changed: {rel} differs from the ledger")

    if compare:
        from . import modeltests, rlstests

        problems += _comparison_problems(root, modeltests, rlstests)
    return problems


# ------------------------------------------------------------------------------------------------- command
def _repo_root() -> Path:
    """UKFR_REPO_ROOT, or the folder above the working directory that holds data/manifest/sources.yml.

    Not `config.find_repo_root`: that module reads YAML, and this one has to run on a bare interpreter.
    """
    env = os.environ.get("UKFR_REPO_ROOT")
    if env:
        return Path(env).resolve()
    here = Path.cwd().resolve()
    for p in (here, *here.parents):
        if (p / "data" / "manifest" / "sources.yml").is_file():
            return p
    raise SystemExit(f"cannot find data/manifest/sources.yml above {here.name}")


def run(args: argparse.Namespace) -> int:
    root = _repo_root()
    if args.action == "write":
        try:
            ledger = write(root)
        except LedgerError as exc:
            print(f"ledger: {exc}", file=sys.stderr)
            return 1
        counts = ", ".join(f"{k} {v}" for k, v in ledger["counts"].items())
        print(f"ledger: wrote {LEDGER.as_posix()}: {len(ledger['files'])} files ({counts})")
        print(f"ledger: model projection {ledger['model']['projection_sha256']}")
        return 0
    problems = check(root, compare=not args.no_compare)
    for p in problems:
        print(f"LEDGER: {p}", file=sys.stderr)
    if problems:
        print(f"ledger: {len(problems)} problem(s)", file=sys.stderr)
        return 1
    stored = json.loads((root / LEDGER).read_text(encoding="utf-8"))
    print(
        f"ledger: ok, {len(stored['files'])} files, model projection {stored['model']['projection_sha256'][:12]}, "
        f"reference {stored['model_reference']['projection_sha256'][:12]}"
    )
    return 0


def add_parser(sub) -> None:
    p = sub.add_parser(
        "ledger",
        help="write or check evidence/ledger.json: the hashes that tie the committed test evidence to the model",
    )
    p.add_argument("action", choices=["write", "check"])
    p.add_argument("--no-compare", action="store_true", help="check: only the hashes, not the two comparisons")
    p.set_defaults(func=run)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m ukfr.ledger")
    ap.add_argument("action", choices=["write", "check"])
    ap.add_argument("--no-compare", action="store_true")
    return run(ap.parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main())
