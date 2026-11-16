"""Filter logic: decide, per discovered file, whether it is fetched, catalogued or ignored."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass

from .config import FileRule, Source
from .discover import Candidate


@dataclass
class Planned:
    cand: Candidate
    action: str  # fetch | catalogue
    note: str
    superseded: bool = False  # a fetch file demoted because a lower tier exists in its release


def rule_for(source: Source, cand: Candidate) -> FileRule | None:
    rules = source.discover[cand.rules_index].files
    if rules is None:
        rules = source.files
    for r in rules:
        if r.matches(cand.filename, cand.title):
            return r
    return None


def plan(source: Source, cands: list[Candidate]) -> list[Planned]:
    """Apply the first matching rule to each file, then the tier preference within each release.

    Within one release only the lowest tier present among `fetch` files is downloaded; files in a
    higher tier hold the same data in another format and are listed as catalogue-only.
    A source with `fetch: false` lists everything as catalogue-only.
    """
    chosen: list[tuple[Candidate, FileRule]] = []
    seen_urls = set()
    for c in cands:
        if c.file_url in seen_urls:
            continue
        r = rule_for(source, c)
        if r is None or r.action == "skip":
            continue
        seen_urls.add(c.file_url)
        chosen.append((c, r))

    best: dict[str, int] = defaultdict(lambda: 10**9)
    for c, r in chosen:
        if r.action == "fetch":
            best[c.release] = min(best[c.release], r.tier)

    out = []
    for c, r in chosen:
        action, note, superseded = r.action, r.note, False
        if action == "fetch" and r.tier > best[c.release]:
            action, superseded = "catalogue", True
            preferred = sorted(
                x.filename
                for x, xr in chosen
                if x.release == c.release and xr.action == "fetch" and xr.tier == best[c.release]
            )
            extra = "same release also published as " + ", ".join(preferred)
            note = f"{note}; {extra}" if note else extra
        if not source.fetch:
            action = "catalogue"
        out.append(Planned(c, action, note, superseded))
    return out
