"""Discovery: turn a source entry into a list of candidate files, without downloading anything.

Four ways to find files:
- page:       one gov.uk Content API page; its details.attachments[] are enumerated.
- collection: a gov.uk collection; links.documents are filtered and each page is enumerated.
- url:        one fixed URL (for files that are not attachments, such as ONS CSV downloads).
- html_index: any HTML page (not gov.uk); <a href> links matching a regex are taken.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from html.parser import HTMLParser
from urllib.parse import unquote, urljoin, urlparse

from .config import Discovery, ReleaseRule, Source
from .http import Client

GOVUK = "https://www.gov.uk"
CONTENT_API = GOVUK + "/api/content"

MONTHS = {
    m: i + 1
    for i, names in enumerate(
        [
            ("january", "jan"),
            ("february", "feb"),
            ("march", "mar"),
            ("april", "apr"),
            ("may",),
            ("june", "jun"),
            ("july", "jul"),
            ("august", "aug"),
            ("september", "sep", "sept"),
            ("october", "oct"),
            ("november", "nov"),
            ("december", "dec"),
        ]
    )
    for m in names
}


@dataclass
class Candidate:
    source_id: str
    release: str
    first_published: str
    public_updated: str
    page_url: str
    file_url: str
    filename: str
    title: str
    content_type: str
    api_bytes: int | None
    rules_index: int  # which discovery entry found it (its file rules apply)


@dataclass
class PageProblem:
    source_id: str
    page_url: str
    url: str
    status: int
    note: str


@dataclass
class Discovered:
    candidates: list[Candidate]
    problems: list[PageProblem]
    pages: list[tuple[int, str, str]]  # (rules_index, release, page_url) for every page seen


def release_label(
    rule: ReleaseRule, *, title: str, path: str, filename: str, attachment_title: str = ""
) -> str | None:
    """Apply a release rule. Groups named `month` become two-digit numbers, `yy` keeps two digits.

    `attachment_title` is the title of one attachment; a page that holds a year of monthly files gives
    each file its own label from it. A month word is matched on its first three letters when the whole
    word is not a month (publishers write "Septmeber")."""
    if rule.source == "value" or rule.value:
        return rule.value
    text = {"title": title, "path": path, "filename": filename, "attachment_title": attachment_title}[rule.source]
    m = re.search(rule.pattern, text or "", flags=re.IGNORECASE)
    if not m:
        return None
    groups = {k: (v or "") for k, v in m.groupdict().items()}
    if "month" in groups and groups["month"]:
        word = groups["month"].lower()
        num = MONTHS.get(word) or (MONTHS.get(word[:3]) if len(word) > 3 else None)
        if num is None:
            return None
        groups["month"] = f"{num:02d}"
    if "yy" in groups:
        groups["yy"] = groups["yy"][-2:]
    for k, v in list(groups.items()):
        groups[k] = v.lower()
    return rule.template.format(**groups) if rule.template else m.group(0).lower()


def in_window(label: str, d: Discovery) -> bool:
    if d.since and label < d.since:
        return False
    if d.until and label > d.until:
        return False
    return True


def _abs(url: str, base: str = GOVUK) -> str:
    return urljoin(base + "/", url) if url.startswith("/") else url


def filename_from_url(url: str) -> str:
    return unquote(urlparse(url).path.rstrip("/").rsplit("/", 1)[-1])


def page_candidates(source: Source, idx: int, d: Discovery, page: dict, path: str) -> list[Candidate]:
    title = page.get("title", "")
    release = release_label(d.release, title=title, path=path, filename="")
    out = []
    for a in page.get("details", {}).get("attachments", []) or []:
        url = _abs(a.get("url", ""))
        if a.get("attachment_type") == "html" or not a.get("filename"):
            fname = filename_from_url(url) + ".html"
            ctype = "text/html"
        else:
            fname = a["filename"]
            ctype = a.get("content_type") or ""
        rel = release
        if rel is None:
            rel = release_label(
                d.release, title=title, path=path, filename=fname, attachment_title=(a.get("title") or "").strip()
            )
        if rel is None:
            continue
        out.append(
            Candidate(
                source_id=source.id,
                release=rel,
                first_published=page.get("first_published_at", "") or "",
                public_updated=page.get("public_updated_at", "") or "",
                page_url=GOVUK + path,
                file_url=url,
                filename=fname,
                title=(a.get("title") or "").strip(),
                content_type=ctype,
                api_bytes=a.get("file_size"),
                rules_index=idx,
            )
        )
    return out


def _collection_docs(coll: dict, d: Discovery) -> list[dict]:
    docs = coll.get("links", {}).get("documents", []) or []
    if d.group:
        ids = set()
        for g in coll.get("details", {}).get("collection_groups", []) or []:
            if g.get("title", "").strip().lower() == d.group.strip().lower():
                ids.update(g.get("documents", []))
        docs = [x for x in docs if x.get("content_id") in ids]
    if d.path_regex:
        docs = [x for x in docs if re.search(d.path_regex, x.get("base_path", ""))]
    if d.title_regex:
        docs = [x for x in docs if re.search(d.title_regex, x.get("title", ""))]
    return docs


class _Links(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[tuple[str, str]] = []
        self._href: str | None = None
        self._text: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self._href = dict(attrs).get("href")
            self._text = []

    def handle_data(self, data):
        if self._href is not None:
            self._text.append(data)

    def handle_endtag(self, tag):
        if tag == "a" and self._href is not None:
            self.links.append((self._href, " ".join("".join(self._text).split())))
            self._href = None


def html_links(html: str, base_url: str) -> list[tuple[str, str]]:
    p = _Links()
    p.feed(html)
    return [(urljoin(base_url, h), t) for h, t in p.links]


def discover(source: Source, client: Client) -> Discovered:
    cands: list[Candidate] = []
    problems: list[PageProblem] = []
    pages: list[tuple[int, str, str]] = []

    def fetch_page(idx: int, d: Discovery, path: str) -> None:
        status, page = client.get_json(CONTENT_API + path)
        if page is None:
            problems.append(PageProblem(source.id, GOVUK + path, CONTENT_API + path, status, "page not served"))
            return
        found = page_candidates(source, idx, d, page, path)
        label = release_label(d.release, title=page.get("title", ""), path=path, filename="")
        if label is not None and not in_window(label, d):
            return
        found = [c for c in found if in_window(c.release, d)]
        if label is not None:
            pages.append((idx, label, GOVUK + path))
        cands.extend(found)

    for idx, d in enumerate(source.discover):
        if d.kind == "page":
            fetch_page(idx, d, d.target)
        elif d.kind == "collection":
            status, coll = client.get_json(CONTENT_API + d.target)
            if coll is None:
                problems.append(
                    PageProblem(source.id, GOVUK + d.target, CONTENT_API + d.target, status, "collection not served")
                )
                continue
            docs = _collection_docs(coll, d)
            # Pre-filter on the release window where the label can be read from the listing.
            kept = []
            for doc in docs:
                label = release_label(d.release, title=doc.get("title", ""), path=doc["base_path"], filename="")
                if label is not None and not in_window(label, d):
                    continue
                kept.append(doc)
            if d.latest:
                kept.sort(key=lambda x: (x.get("public_updated_at") or "", x["base_path"]), reverse=True)
                kept = kept[: d.latest]
            for doc in sorted(kept, key=lambda x: x["base_path"]):
                fetch_page(idx, d, doc["base_path"])
        elif d.kind == "url":
            fname = d.filename or filename_from_url(d.target)
            label = release_label(d.release, title="", path=urlparse(d.target).path, filename=fname)
            if label is None:
                continue
            pages.append((idx, label, d.page_url or d.target))
            cands.append(
                Candidate(
                    source_id=source.id,
                    release=label,
                    first_published="",
                    public_updated="",
                    page_url=d.page_url or "",
                    file_url=d.target,
                    filename=fname,
                    title="",
                    content_type="",
                    api_bytes=None,
                    rules_index=idx,
                )
            )
        elif d.kind == "html_index":
            status, html = client.get_text(d.target)
            if status != 200:
                problems.append(PageProblem(source.id, d.target, d.target, status, "index page not served"))
                continue
            seen = set()
            for href, text in html_links(html, d.target):
                if d.link_regex and not re.search(d.link_regex, href):
                    continue
                if href in seen:
                    continue
                seen.add(href)
                fname = filename_from_url(href)
                label = release_label(d.release, title=text, path=urlparse(href).path, filename=fname)
                if label is None or not in_window(label, d):
                    continue
                pages.append((idx, label, d.target))
                cands.append(
                    Candidate(
                        source_id=source.id,
                        release=label,
                        first_published="",
                        public_updated="",
                        page_url=d.target,
                        file_url=href,
                        filename=fname,
                        title=text,
                        content_type="",
                        api_bytes=None,
                        rules_index=idx,
                    )
                )
        else:  # pragma: no cover - rejected when the config is parsed
            raise ValueError(d.kind)
    return Discovered(cands, problems, pages)
