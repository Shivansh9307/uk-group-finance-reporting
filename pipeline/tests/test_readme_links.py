"""Every relative link and image in the README and the docs resolves to a file in the repository.

Scope: `README.md`, `docs/*.md` and `docs/adr/*.md`. A relative target must exist, with the case of every path part as git
stores it (a Windows checkout ignores case, a Linux runner does not). An anchor that points at a Markdown file is checked
against the headings of that file, with GitHub's rule for turning a heading into an anchor. An external link (`https://`)
is listed and never fetched. Run the module to print the counts: `python -I pipeline/tests/test_readme_links.py`.
"""

from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import unquote

import pytest

FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
INLINE_CODE = re.compile(r"(`+)(.+?)\1")
# [text](target) and ![alt](target); the target may be <wrapped> and may carry a "title".
MD_LINK = re.compile(r"!?\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*(<[^>]*>|[^)\s]+)(?:\s+(?:\"[^\"]*\"|'[^']*'))?\s*\)")
# [label]: target   (reference definitions)
REF_DEF = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*(<[^>]*>|\S+)")
HTML_ATTR = re.compile(r"""\b(?:src|href)\s*=\s*(?:"([^"]*)"|'([^']*)')""", re.IGNORECASE)
HEADING = re.compile(r"^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$")
EXTERNAL = ("https://", "http://", "mailto:", "ftp://")


@dataclass(frozen=True)
class Link:
    source: Path  # relative to the repository root, forward slashes
    line: int
    target: str


def _documents(root: Path) -> list[Path]:
    files = [root / "README.md"]
    files += sorted((root / "docs").glob("*.md"))
    files += sorted((root / "docs" / "adr").glob("*.md"))
    return [f for f in files if f.is_file()]


def _strip_code(text: str) -> list[tuple[int, str]]:
    """Lines of the text outside fenced blocks, with inline code replaced by a placeholder of the same length."""
    out: list[tuple[int, str]] = []
    fence: str | None = None
    for number, line in enumerate(text.splitlines(), start=1):
        m = FENCE.match(line)
        if m:
            marker = m.group(1)
            if fence is None:
                fence = marker[0] * len(marker)
            elif marker[0] == fence[0] and len(marker) >= len(fence):
                fence = None
            continue
        if fence is not None:
            continue
        out.append((number, INLINE_CODE.sub(lambda mm: "x" * len(mm.group(0)), line)))
    return out


def _links(root: Path, path: Path) -> list[Link]:
    rel = path.relative_to(root).as_posix()
    found: list[Link] = []
    for number, line in _strip_code(path.read_text(encoding="utf-8")):
        targets = [m.group(1) for m in MD_LINK.finditer(line)]
        targets += [m.group(1) or m.group(2) for m in HTML_ATTR.finditer(line)]
        ref = REF_DEF.match(line)
        if ref:
            targets.append(ref.group(1))
        for target in targets:
            target = target.strip()
            if target.startswith("<") and target.endswith(">"):
                target = target[1:-1].strip()
            if target:
                found.append(Link(Path(rel), number, target))
    return found


def _slug(heading: str) -> str:
    """GitHub's anchor for a heading: markup removed, lower case, punctuation dropped, spaces to hyphens."""
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", heading)  # [text](url) -> text
    text = re.sub(r"[`*]", "", text).strip().lower()
    text = re.sub(r"[^\w\- ]", "", text)  # letters, digits, underscore, hyphen, space
    return text.replace(" ", "-")


def _anchors(path: Path) -> set[str]:
    seen: dict[str, int] = {}
    anchors: set[str] = set()
    fence: str | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        m = FENCE.match(line)
        if m:
            marker = m.group(1)
            if fence is None:
                fence = marker[0] * len(marker)
            elif marker[0] == fence[0] and len(marker) >= len(fence):
                fence = None
            continue
        if fence is not None:
            continue
        h = HEADING.match(line)
        if not h:
            continue
        base = _slug(h.group(2))
        n = seen.get(base, 0)
        seen[base] = n + 1
        anchors.add(base if n == 0 else f"{base}-{n}")
    return anchors


def _resolve_exact(root: Path, candidate: Path) -> Path | None:
    """The path, if it exists inside the repository with exactly this spelling of every part."""
    # No resolve(): on Windows it would return the case the file system holds and hide a wrong-case link.
    base = os.path.normpath(os.path.abspath(root))
    full = os.path.normpath(os.path.abspath(candidate))
    if full != base and not full.startswith(base + os.sep):
        return None
    parts = Path(full[len(base) :].lstrip("\\/")).parts if full != base else ()
    here = Path(base)
    for part in parts:
        try:
            names = {p.name for p in here.iterdir()}
        except (NotADirectoryError, PermissionError):
            return None
        if part not in names:
            return None
        here = here / part
    return here


def check(root: Path) -> tuple[list[str], int, list[Link]]:
    """Problems found, the number of internal links checked, and the external links."""
    problems: list[str] = []
    internal = 0
    external: list[Link] = []
    anchors_of: dict[Path, set[str]] = {}
    for doc in _documents(root):
        for link in _links(root, doc):
            where = f"{link.source}:{link.line}"
            target = link.target
            if target.lower().startswith(EXTERNAL):
                external.append(link)
                continue
            internal += 1
            path_part, _, fragment = target.partition("#")
            path_part = unquote(path_part.partition("?")[0])
            if path_part.startswith("/") or re.match(r"^[A-Za-z]:[\\/]", path_part):
                problems.append(f"{where}: {target!r} is an absolute path; use a path relative to the file")
                continue
            base = doc if path_part == "" else (doc.parent / path_part)
            resolved = _resolve_exact(root, base)
            if resolved is None:
                problems.append(f"{where}: {target!r} does not resolve to a file or folder in the repository")
                continue
            if fragment and resolved.is_file() and resolved.suffix.lower() == ".md":
                if resolved not in anchors_of:
                    anchors_of[resolved] = _anchors(resolved)
                if unquote(fragment).lower() not in anchors_of[resolved]:
                    problems.append(
                        f"{where}: {target!r}: no heading of {Path(os.path.relpath(resolved, root)).as_posix()} "
                        f"has the anchor #{fragment}"
                    )
    return problems, internal, external


def test_slug_follows_the_rule_github_uses():
    assert _slug("Register of real, authored, derived and synthetic data") == (
        "register-of-real-authored-derived-and-synthetic-data"
    )
    assert _slug("What \"independent\" means") == "what-independent-means"
    assert _slug("9. Plan variance reconciliation (full scope)") == "9-plan-variance-reconciliation-full-scope"
    assert _slug("Known residuals (published, not hidden)") == "known-residuals-published-not-hidden"
    assert _slug("The `Outturn` measure") == "the-outturn-measure"


def test_the_checker_finds_a_broken_link_a_broken_anchor_and_ignores_code(tmp_path):
    (tmp_path / "docs" / "adr").mkdir(parents=True)
    (tmp_path / "docs" / "page.md").write_text("# Page\n\n## A heading\n\n## A heading\n", encoding="utf-8")
    (tmp_path / "README.md").write_text(
        "# Title\n"
        "[ok](docs/page.md) [ok anchor](docs/page.md#a-heading-1) [bad anchor](docs/page.md#nope)\n"
        "[missing](docs/none.md) ![image](shots/none.png) [web](https://example.org/x)\n"
        "[wrong case](Docs/page.md) [here](#title) [bad here](#nothing)\n"
        "`[in code](docs/none.md)`\n"
        "```\n[in fence](docs/none.md)\n```\n",
        encoding="utf-8",
    )
    problems, internal, external = check(tmp_path)
    text = "\n".join(problems)
    assert "docs/none.md" in text and "shots/none.png" in text and "#nope" in text and "Docs/page.md" in text
    assert "#nothing" in text
    assert "in code" not in text and "in fence" not in text
    assert len(problems) == 5
    assert internal == 8
    assert [link.target for link in external] == ["https://example.org/x"]


def test_every_relative_link_and_image_in_the_readme_and_the_docs_resolves(repo_root):
    problems, internal, _ = check(repo_root)
    assert internal > 0, "no relative link was found: the parser is broken"
    assert not problems, "\n" + "\n".join(problems)


def test_external_links_are_https_and_are_only_listed(repo_root, capsys):
    _, _, external = check(repo_root)
    insecure = [f"{link.source}:{link.line}: {link.target}" for link in external if link.target.startswith("http://")]
    assert not insecure, "use https:\n" + "\n".join(insecure)
    with capsys.disabled():
        print(f"\nexternal links listed, not fetched: {len(external)}")


if __name__ == "__main__":
    here = Path(__file__).resolve()
    root = next(p for p in here.parents if (p / "README.md").is_file() and (p / "pipeline").is_dir())
    found, n_internal, links = check(root)
    for item in found:
        print(item)
    docs = _documents(root)
    print(f"documents checked: {len(docs)}")
    print(f"internal links checked: {n_internal}, problems: {len(found)}")
    print(f"external links listed, not fetched: {len(links)}")
    sys.exit(1 if found else 0)
