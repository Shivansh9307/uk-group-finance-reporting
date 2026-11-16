import json

from conftest import FIXTURES, FakeWeb

from ukfr.config import Discovery, ReleaseRule, Source, parse_settings
from ukfr.discover import discover, html_links, page_candidates, release_label

TITLE_RULE = ReleaseRule(
    source="title", pattern=r"(?P<month>[A-Za-z]+)\s+(?P<year>\d{4})\s*$", template="{year}-{month}"
)


def _source(*discover_entries):
    return Source(id="s", title="t", publisher="p", licence="l", discover=list(discover_entries))


def test_page_attachments_are_enumerated_with_html_attachments_named():
    page = json.loads((FIXTURES / "page_inyear_sep_2026.json").read_text(encoding="utf-8"))
    d = Discovery(kind="page", target=page["base_path"], release=TITLE_RULE)
    cands = page_candidates(_source(d), 0, d, page, page["base_path"])
    assert [c.filename for c in cands] == [
        "OSCAR_in-year_dataset_guidance.pdf",
        "oscar-in-year-dataset-guidance.html",
        "OSCAR_in_year_dataset_Sep_2026.csv",
        "OSCAR_in_year_dataset_September_2026_.xlsm",
    ]
    assert {c.release for c in cands} == {"2026-09"}
    html = cands[1]
    assert html.content_type == "text/html"
    assert html.file_url.startswith("https://www.gov.uk/government/publications/")
    csv = cands[2]
    assert csv.api_bytes == 4807557
    assert csv.title == "OSCAR in year dataset"  # trailing space trimmed
    assert csv.first_published == "2026-09-22T09:30:02+01:00"
    assert csv.page_url == "https://www.gov.uk" + page["base_path"]


def test_release_labels():
    assert release_label(TITLE_RULE, title="OSCAR: September 2026", path="", filename="") == "2026-09"
    assert release_label(TITLE_RULE, title="OSCAR: Sept 2021 ", path="", filename="") == "2021-09"
    assert release_label(TITLE_RULE, title="no date here", path="", filename="") is None
    est = ReleaseRule(
        source="path", pattern=r"main-supply-estimates-(?P<y1>\d{4})-to-(?P<yy>\d{2,4})$", template="{y1}-{yy}-mains"
    )
    assert release_label(est, title="", path="/x/main-supply-estimates-2026-to-2027", filename="") == "2026-27-mains"
    assert release_label(est, title="", path="/x/main-supply-estimates-2022-to-23", filename="") == "2022-23-mains"
    assert release_label(ReleaseRule(value="latest"), title="", path="", filename="") == "latest"


def test_collection_crawl_filters_group_and_since(web: FakeWeb):
    d = Discovery(
        kind="collection",
        target="/government/collections/hmt-oscar-publishing-from-the-database",
        release=TITLE_RULE,
        group="In-year data",
        since="2019-03",
    )
    found = discover(_source(d), web.client())
    assert sorted({c.release for c in found.candidates}) == ["2019-03", "2026-03", "2026-09"]
    # December 2018 is before `since` and is never requested; the annual page is in another group.
    assert not web.gets("december-2018")
    assert not web.gets("annual-release")
    assert found.problems == []


def test_collection_latest_keeps_most_recent(web: FakeWeb):
    d = Discovery(
        kind="collection",
        target="/government/collections/hmt-oscar-publishing-from-the-database",
        release=TITLE_RULE,
        group="In-year data",
        latest=2,
    )
    found = discover(_source(d), web.client())
    assert sorted({c.release for c in found.candidates}) == ["2026-03", "2026-09"]


def test_missing_page_is_a_problem_not_a_crash(web: FakeWeb):
    d = Discovery(kind="page", target="/government/publications/gone", release=TITLE_RULE)
    found = discover(_source(d), web.client())
    assert found.candidates == []
    assert [(p.status, p.note) for p in found.problems] == [(404, "page not served")]


def test_html_index_scrapes_links_from_a_non_govuk_page():
    web = FakeWeb()
    index = "https://www.example.org/financial-accounting/tac-data/"
    web.add(index, (FIXTURES / "html_index.html").read_text(encoding="utf-8"))
    d = Discovery(
        kind="html_index",
        target=index,
        link_regex=r"TAC-data-\d{4}-\d{2}\.xlsx$",
        release=ReleaseRule(source="filename", pattern=r"(?P<y>\d{4})-(?P<yy>\d{2})", template="{y}-{yy}"),
    )
    found = discover(_source(d), web.client())
    assert [(c.release, c.file_url) for c in found.candidates] == [
        ("2024-25", "https://www.example.org/wp-content/uploads/2025/11/TAC-data-2024-25.xlsx"),
        ("2023-24", "https://www.example.org/wp-content/uploads/2024/11/TAC-data-2023-24.xlsx"),
    ]
    assert found.candidates[0].title == "TAC data publication 2024/25"


def test_html_links_resolves_relative_urls():
    links = html_links('<a href="a/b.xlsx">x</a><a href="/c.csv"> y  z </a>', "https://h.example/p/")
    assert links == [("https://h.example/p/a/b.xlsx", "x"), ("https://h.example/c.csv", "y z")]


def test_parse_settings_rejects_ambiguous_discovery():
    raw = {
        "sources": [{"id": "x", "title": "", "publisher": "", "licence": "", "discover": [{"page": "/a", "url": "b"}]}]
    }
    try:
        parse_settings(raw)
    except ValueError as e:
        assert "exactly one" in str(e)
    else:  # pragma: no cover
        raise AssertionError("expected ValueError")
