"""The summary of a build log and a test run is deterministic, refuses a dirty run and refuses a local path."""

from __future__ import annotations

import pytest

from ukfr import build_summary as bs

BUILD_LOG = """build scope=full target=localhost / UKGroupFinance_x (Windows integrated authentication)
  creating database UKGroupFinance_x
database: 1.5 s
  sql raw/001_oscar_inyear.sql (3 batches)
pre sql: 0.1 s
stage authored: 0.3 s
  authored: {'account_flow': 12, 'sr_group': 32}
stage oscar_inyear: 100.2 s
  oscar_inyear: {'files': 32, 'rows_loaded': 1547078}
post sql: 90.0 s
audit export: 0.5 s
  wrote table_counts.csv
"""
PYTEST_LOG = """.....
325 passed in 80.12s (0:01:20)
"""


def test_the_build_log_gives_steps_row_counts_and_a_total():
    scope, rows = bs.parse_build_log(BUILD_LOG)
    assert scope == "full"
    assert ("step", "stage oscar_inyear", "100.2", "s") in rows
    assert ("rows", "authored.sr_group", "32", "rows") in rows
    assert ("rows", "oscar_inyear.rows_loaded", "1547078", "rows") in rows
    assert rows[-1] == ("total", "sum of the timed steps", "192.6", "s")


def test_the_pytest_summary_line_is_read_with_or_without_skips():
    assert bs.parse_pytest_log(PYTEST_LOG) == {
        "passed": "325",
        "failed": "0",
        "errors": "0",
        "skipped": "0",
        "duration_s": "80.12",
    }
    got = bs.parse_pytest_log("306 passed, 30 skipped in 40.54s\n")
    assert got["skipped"] == "30" and got["duration_s"] == "40.54"


def test_the_same_logs_give_the_same_bytes_and_a_run_with_skips_is_refused(tmp_path):
    (tmp_path / "b.log").write_text(BUILD_LOG, encoding="utf-8")
    (tmp_path / "p.log").write_text(PYTEST_LOG, encoding="utf-8")
    first = {
        p.name: p.read_bytes() for p in bs.write_all(tmp_path / "b.log", tmp_path / "p.log", tmp_path / "a", None, True)
    }
    second = {
        p.name: p.read_bytes() for p in bs.write_all(tmp_path / "b.log", tmp_path / "p.log", tmp_path / "b", None, True)
    }
    assert first == second and b"\r" not in first["build_summary.csv"]
    (tmp_path / "p2.log").write_text("306 passed, 30 skipped in 40.54s\n", encoding="utf-8")
    with pytest.raises(bs.SummaryError):
        bs.write_all(tmp_path / "b.log", tmp_path / "p2.log", tmp_path / "c", None, True)
    assert not (tmp_path / "c").exists()


def test_a_local_path_or_a_user_name_in_the_input_stops_the_write(tmp_path):
    (tmp_path / "b.log").write_text(BUILD_LOG, encoding="utf-8")
    (tmp_path / "p.log").write_text(PYTEST_LOG, encoding="utf-8")
    counts = tmp_path / "table_counts.csv"
    counts.write_text("schema_name,table_name,row_count\nraw,C:\\Users\\someone\\x,1\n", encoding="utf-8")
    with pytest.raises(bs.SummaryError):
        bs.write_all(tmp_path / "b.log", tmp_path / "p.log", tmp_path / "out", counts, True)
    assert not (tmp_path / "out").exists()
