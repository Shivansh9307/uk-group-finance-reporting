import json

from conftest import SOURCES

from ukfr.config import FILES_CSV, load_settings
from ukfr.fetch import run_fetch
from ukfr.manifest import read_rows, write_rows
from ukfr.verify import verify

SEP_CSV = "data/committed/oscar_inyear/2026-09/OSCAR_in_year_dataset_Sep_2026.csv"


def fetched_repo(repo, web):
    s = run_fetch(repo, load_settings(repo), web.client(), log=lambda *_: None)
    assert s.ok
    return repo


def test_verify_passes_after_fetch(repo, web):
    fetched_repo(repo, web)
    res = verify(repo, load_settings(repo))
    assert res.ok, res.failures
    assert res.committed_ok == 4  # two zips, the Sep 2026 CSV, the March 2026 ODS
    assert res.raw_ok == 1 and res.dead == 1 and res.not_present == 0
    assert res.line().startswith("verify: 4 committed files ok, 1 raw files ok, 0 not present locally, 1 dead")


def test_verify_fails_on_changed_committed_file(repo, web):
    fetched_repo(repo, web)
    (repo / SEP_CSV).write_bytes(b"tampered")
    res = verify(repo, load_settings(repo))
    assert not res.ok and "does not match the manifest" in res.failures[0]


def test_verify_fails_on_missing_committed_file(repo, web):
    fetched_repo(repo, web)
    (repo / SEP_CSV).unlink()
    res = verify(repo, load_settings(repo))
    assert not res.ok and res.failures == [f"missing committed file {SEP_CSV}"]


def test_raw_files_absent_locally_are_reported_not_failed(repo, web, tmp_path, monkeypatch):
    fetched_repo(repo, web)
    monkeypatch.setenv("UKFR_DATA_DIR", str(tmp_path / "elsewhere"))
    res = verify(repo, load_settings(repo))
    assert res.ok and res.not_present == 1 and res.raw_ok == 0


def test_unlisted_committed_file_fails(repo, web):
    fetched_repo(repo, web)
    extra = repo / "data/committed/oscar_inyear/2026-09/stray.csv"
    extra.write_text("x", encoding="utf-8")
    res = verify(repo, load_settings(repo))
    assert not res.ok and "not in the manifest" in res.failures[0]


def test_volatile_source_mismatch_is_a_warning(repo, web, tmp_path):
    raw = json.loads(json.dumps(SOURCES))
    raw["sources"][1]["volatile"] = True
    (repo / "data/manifest/sources.yml").write_text(json.dumps(raw), encoding="utf-8")
    fetched_repo(repo, web)
    (tmp_path / "raw/oscar_annual/2024-11/BUD_2019-20.xlsx").write_bytes(b"new month")
    res = verify(repo, load_settings(repo))
    assert res.ok and res.volatile_changed == 1 and res.warnings


def test_fetched_row_without_hash_fails(repo, web):
    fetched_repo(repo, web)
    rows = read_rows(repo / FILES_CSV)
    for r in rows:
        if r.filename == "BUD_2019-20.xlsx":
            r.sha256 = ""
    write_rows(repo / FILES_CSV, rows)
    res = verify(repo, load_settings(repo))
    assert not res.ok and "no sha256" in res.failures[0]
