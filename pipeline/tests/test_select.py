from dataclasses import replace

from ukfr.config import Discovery, FileRule, ReleaseRule, Source
from ukfr.discover import Candidate
from ukfr.select import plan


def cand(release, filename, title="", idx=0):
    return Candidate(
        source_id="s",
        release=release,
        first_published="",
        public_updated="",
        page_url="https://www.gov.uk/p",
        file_url=f"https://assets.example/{release}/{filename}",
        filename=filename,
        title=title,
        content_type="",
        api_bytes=1,
        rules_index=idx,
    )


RULES = [
    FileRule(match="(?i)guidance", action="catalogue", note="guidance"),
    FileRule(match=r"(?i)\.(zip|csv)$", action="fetch", tier=1),
    FileRule(match=r"(?i)\.(ods|xlsm)$", action="fetch", tier=2),
]


def source(rules=RULES, fetch=True, item_rules=None):
    d = Discovery(kind="page", target="/p", release=ReleaseRule(value="r"), files=item_rules)
    return Source(id="s", title="", publisher="", licence="", discover=[d], files=rules, fetch=fetch)


def actions(planned):
    return {(p.cand.release, p.cand.filename): (p.action, p.superseded) for p in planned}


def test_first_matching_rule_wins_and_unmatched_files_are_ignored():
    got = actions(plan(source(), [cand("r1", "x_guidance.zip"), cand("r1", "data.csv"), cand("r1", "notes.docx")]))
    assert got == {("r1", "x_guidance.zip"): ("catalogue", False), ("r1", "data.csv"): ("fetch", False)}


def test_lower_tier_supersedes_other_formats_within_a_release_only():
    planned = plan(
        source(),
        [cand("r1", "a.zip"), cand("r1", "a.ods"), cand("r2", "b.ods"), cand("r3", "c.csv"), cand("r3", "c.xlsm")],
    )
    got = actions(planned)
    assert got[("r1", "a.zip")] == ("fetch", False)
    assert got[("r1", "a.ods")] == ("catalogue", True)
    assert got[("r2", "b.ods")] == ("fetch", False)  # no zip/csv in that release: keep the ODS
    assert got[("r3", "c.xlsm")] == ("catalogue", True)
    note = next(p.note for p in planned if p.cand.filename == "a.ods")
    assert note == "same release also published as a.zip"


def test_title_rule_must_match_too():
    rules = [FileRule(match=r"\.xlsx$", title="^Departmental DEL budgets", action="fetch")]
    got = actions(
        plan(
            source(rules),
            [cand("r", "a.xlsx", "Departmental DEL budgets: tables"), cand("r", "b.xlsx", "Estimates memorandum")],
        )
    )
    assert got == {("r", "a.xlsx"): ("fetch", False)}


def test_fetch_false_lists_everything_as_catalogue():
    got = actions(plan(source(fetch=False), [cand("r1", "a.zip")]))
    assert got == {("r1", "a.zip"): ("catalogue", False)}


def test_discovery_item_rules_override_source_rules_and_duplicates_drop():
    s = source(item_rules=[FileRule(match=r"^only\.zip$", action="fetch")])
    c = cand("r", "only.zip")
    got = plan(s, [c, replace(c), cand("r", "data.csv")])
    assert [(p.cand.filename, p.action) for p in got] == [("only.zip", "fetch")]
