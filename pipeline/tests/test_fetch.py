import random
from dataclasses import replace

from conftest import ASSETS, FakeWeb

from ukfr.config import DEAD_LINKS_CSV, FILES_CSV, load_settings
from ukfr.fetch import run_fetch
from ukfr.manifest import Row, read_dead, read_rows, write_rows


def by_name(rows):
    return {r.filename: r for r in rows}


def fetch(repo, web: FakeWeb, **kw):
    return run_fetch(repo, load_settings(repo), web.client(), log=lambda *_: None, **kw)


def test_fetch_downloads_commits_and_records_manifest(repo, web, tmp_path):
    s = fetch(repo, web)
    assert s.ok, s.errors
    rows = read_rows(repo / FILES_CSV)
    inyear = by_name(r for r in rows if r.source_id == "oscar_inyear")

    csv = inyear["OSCAR_in_year_dataset_Sep_2026.csv"]
    assert csv.fetched == "yes" and csv.http_status == "200"
    assert csv.path == "data/committed/oscar_inyear/2026-09/OSCAR_in_year_dataset_Sep_2026.csv"
    assert (repo / csv.path).read_bytes() == b"Organisation Code,Amount\r\nA,1\r\n"  # bytes kept as served
    assert len(csv.sha256) == 64 and csv.bytes == "31"

    assert inyear["OSCAR_in_year_dataset_September_2026_.xlsm"].fetched == "no"
    guidance = [r for r in rows if r.notes.startswith("release guidance")]
    assert guidance and all(r.fetched == "no" and r.sha256 == "" for r in guidance)
    html = inyear["oscar-in-year-dataset-guidance.html"]
    assert (html.content_type, html.bytes, html.http_status) == ("text/html", "", "200")  # length drifts per request

    # March 2019: the zip holds a CSV, so the ODS is catalogue-only.
    assert inyear["OSCAR_in-year_dataset_21Mar2019.zip"].zip_members == "OSCAR_in-year_dataset_21Mar2019.csv|deflate|31"
    assert inyear["OSCAR_in-year_dataset_21Mar2019.ods"].fetched == "no"
    # March 2026: the zip holds only an ODS, so the standalone ODS is fetched as well.
    assert inyear["OSCAR_in_year_dataset_March_2026.zip"].fetched == "yes"
    assert inyear["OSCAR_in_year_dataset_March_2026.ods"].fetched == "yes"

    # Non-committed sources land under $UKFR_DATA_DIR and are recorded with a portable path.
    bud = by_name(rows)["BUD_2019-20.xlsx"]
    assert bud.path == "$UKFR_DATA_DIR/oscar_annual/2024-11/BUD_2019-20.xlsx"
    assert (tmp_path / "raw" / "oscar_annual" / "2024-11" / "BUD_2019-20.xlsx").is_file()
    assert not list((repo / "data" / "committed").rglob("BUD*"))


def test_dead_link_is_recorded_not_raised(repo, web):
    s = fetch(repo, web)
    assert s.ok
    mfo = by_name(read_rows(repo / FILES_CSV))["MFO_23-24.zip"]
    assert (mfo.fetched, mfo.http_status, mfo.sha256) == ("dead", "404", "")
    dead = read_dead(repo / DEAD_LINKS_CSV)
    assert [(d.filename, d.http_status, d.page_url) for d in dead] == [
        ("MFO_23-24.zip", "404", "https://www.gov.uk/government/publications/oscar-annual-release-november-2024")
    ]


def test_rerun_resumes_without_downloading_again(repo, web):
    fetch(repo, web)
    first = (repo / FILES_CSV).read_bytes()
    asset_gets = len(web.gets(ASSETS))
    s = fetch(repo, web)
    assert s.ok and s.downloaded == 0 and s.skipped >= 4
    assert len(web.gets(ASSETS)) - asset_gets == 1  # only the dead MFO link is tried again
    assert (repo / FILES_CSV).read_bytes() == first


def test_corrupt_local_file_is_refetched(repo, web):
    fetch(repo, web)
    path = repo / "data/committed/oscar_inyear/2026-09/OSCAR_in_year_dataset_Sep_2026.csv"
    path.write_bytes(b"damaged")
    s = fetch(repo, web)
    assert s.ok and s.downloaded == 1
    assert path.read_bytes().startswith(b"Organisation Code")


def test_changed_file_at_source_fails_loudly(repo, web):
    fetch(repo, web)
    url = ASSETS + "/6ab103192f29b3888481876f/OSCAR_in_year_dataset_Sep_2026.csv"
    web.add(url, "Organisation Code,Amount\r\nA,999\r\n")
    path = repo / "data/committed/oscar_inyear/2026-09/OSCAR_in_year_dataset_Sep_2026.csv"
    path.unlink()  # force a download
    before = by_name(read_rows(repo / FILES_CSV))["OSCAR_in_year_dataset_Sep_2026.csv"].sha256
    s = fetch(repo, web)
    assert not s.ok and "changed at source" in s.errors[0]
    assert by_name(read_rows(repo / FILES_CSV))["OSCAR_in_year_dataset_Sep_2026.csv"].sha256 == before
    assert not path.exists() and not path.with_name(path.name + ".part").exists()
    s = fetch(repo, web, accept_changes=True)
    assert s.ok and path.read_bytes().endswith(b"999\r\n")


def test_catalogue_only_downloads_nothing(repo, web):
    s = fetch(repo, web, catalogue_only=True)
    assert s.ok and s.downloaded == 0
    assert not web.gets(ASSETS)  # HEAD requests only
    rows = read_rows(repo / FILES_CSV)
    assert rows and all(r.fetched in ("no", "dead") for r in rows)
    assert by_name(rows)["BUD_2019-20.xlsx"].bytes == "12138817"  # size from the API


def test_partial_run_keeps_other_sources(repo, web):
    fetch(repo, web)
    s = fetch(repo, web, source_ids=["oscar_annual"])
    assert s.ok
    assert {r.source_id for r in read_rows(repo / FILES_CSV)} == {"oscar_inyear", "oscar_annual"}
    assert {d.source_id for d in read_dead(repo / DEAD_LINKS_CSV)} == {"oscar_annual"}


def test_commit_limit_stops_before_downloading(repo, web):
    raw = (repo / "data/manifest/sources.yml").read_text(encoding="utf-8")
    (repo / "data/manifest/sources.yml").write_text(
        raw.replace('"commit_limit_mb": 60', '"commit_limit_mb": 1'), encoding="utf-8"
    )
    s = fetch(repo, web, source_ids=["oscar_inyear"])
    assert not s.ok and "over the 1 MB limit" in s.errors[0]
    assert not web.gets(ASSETS)


def _row(**kw):
    base = dict.fromkeys(Row.__dataclass_fields__, "")
    base.update(kw)
    return Row(**base)


def test_manifest_order_is_deterministic(tmp_path):
    rows = [
        _row(source_id=s, release=r, filename=f, file_url=f"u/{f}")
        for s in ("b", "a")
        for r in ("2026-09", "2019-03")
        for f in ("y.zip", "x.csv")
    ]
    a, b = tmp_path / "a.csv", tmp_path / "b.csv"
    write_rows(a, rows)
    shuffled = rows[:]
    random.Random(7).shuffle(shuffled)
    write_rows(b, [replace(r) for r in shuffled])
    assert a.read_bytes() == b.read_bytes()
    assert b"\r\n" not in a.read_bytes()
    first = [(r.source_id, r.release, r.filename) for r in read_rows(a)][:3]
    assert first == [("a", "2019-03", "x.csv"), ("a", "2019-03", "y.zip"), ("a", "2026-09", "x.csv")]


def test_manifest_rejects_duplicate_rows(tmp_path):
    r = _row(source_id="a", release="r", filename="f", file_url="u")
    try:
        write_rows(tmp_path / "m.csv", [r, replace(r)])
    except ValueError as e:
        assert "duplicate" in str(e)
    else:  # pragma: no cover
        raise AssertionError("expected ValueError")
