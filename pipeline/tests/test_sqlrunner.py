"""The SQL file discovery and batch splitting (no database)."""

from __future__ import annotations

from pathlib import Path

import pytest

from ukfr import sqlrunner
from ukfr.config import find_repo_root
from ukfr.sqlrunner import SqlLayoutError


def test_split_on_go_lines_only_and_track_start_lines():
    text = "SELECT 1;\nGO\n\nSELECT 2\nSELECT 3;\ngo 5\n-- just a comment\nGO\nSELECT 'GO now';\n"
    batches = sqlrunner.split_batches(text)
    assert [b.text for b in batches] == ["SELECT 1;", "SELECT 2\nSELECT 3;", "SELECT 'GO now';"]
    assert [b.line for b in batches] == [1, 4, 9]


def test_a_file_of_comments_and_gos_has_no_batches():
    assert sqlrunner.split_batches("-- nothing\nGO\n/* still nothing */\nGO\n") == []


def test_header_directives_are_read_from_the_top_only():
    text = "-- phase: pre\n-- scope: full\n-- test: x holds\nSELECT 1\n" + "\n" * 20 + "-- phase: post\n"
    assert sqlrunner.header_directives(text) == {"phase": "pre", "scope": "full", "test": "x holds"}


def make(tmp_path: Path, files: dict[str, str]) -> Path:
    for rel, text in files.items():
        p = tmp_path / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
    return tmp_path


def test_order_is_layer_then_prefix_and_phase_defaults_follow_the_layer(tmp_path):
    root = make(
        tmp_path,
        {
            "audit/010_c.sql": "SELECT 1",
            "stg/020_b.sql": "SELECT 1",
            "stg/010_a.sql": "SELECT 1",
            "raw/005_land.sql": "SELECT 1",
            "authored/001_landing.sql": "-- phase: pre\nSELECT 1",
            "dw/050_scale_only.sql": "-- scope: full\nSELECT 1",
            "tests/001_check.sql": "-- test: x\nSELECT 1",
            "README.md": "ignored",
        },
    )
    found = sqlrunner.discover(root)
    assert [f.rel for f in found] == [
        "raw/005_land.sql",
        "authored/001_landing.sql",
        "stg/010_a.sql",
        "stg/020_b.sql",
        "dw/050_scale_only.sql",
        "audit/010_c.sql",
    ]
    committed = sqlrunner.select(found, "post", "committed")
    full = sqlrunner.select(found, "post", "full")
    assert [f.rel for f in committed] == ["stg/010_a.sql", "stg/020_b.sql", "audit/010_c.sql"]
    assert "dw/050_scale_only.sql" in [f.rel for f in full]
    assert [f.rel for f in sqlrunner.select(found, "pre", "committed")] == [
        "raw/005_land.sql",
        "authored/001_landing.sql",
    ]


@pytest.mark.parametrize(
    "files, message",
    [
        ({"stray/010_a.sql": "SELECT 1"}, "unknown layer folder"),
        ({"stg/10_a.sql": "SELECT 1"}, "three digits"),
        ({"stg/010_A.sql": "SELECT 1"}, "lower case"),
        ({"stg/010_a.sql": "SELECT 1", "stg/010_b.sql": "SELECT 1"}, "use prefix 010"),
        ({"010_a.sql": "SELECT 1"}, "belong in a layer folder"),
        ({"stg/010_a.sql": "-- phase: later\nSELECT 1"}, "phase must be"),
        ({"stg/010_a.sql": "-- scope: everywhere\nSELECT 1"}, "scope must be"),
    ],
)
def test_layout_errors_are_loud(tmp_path, files, message):
    with pytest.raises(SqlLayoutError, match=message):
        sqlrunner.discover(make(tmp_path, files))


class FakeDb:
    def __init__(self, fail_on: str | None = None):
        self.fail_on = fail_on
        self.ran: list[str] = []

    def execute(self, sql: str) -> None:
        if self.fail_on and self.fail_on in sql:
            raise RuntimeError("Invalid object name 'nope'")
        self.ran.append(sql)


def test_a_failing_batch_names_the_file_and_batch(tmp_path):
    root = make(tmp_path, {"stg/010_a.sql": "SELECT 1;\nGO\nSELECT * FROM nope;\nGO\nSELECT 3;"})
    (f,) = sqlrunner.discover(root)
    db = FakeDb(fail_on="nope")
    with pytest.raises(sqlrunner.SqlRunError) as err:
        sqlrunner.run_file(db, f)
    assert "stg/010_a.sql batch 2 of 3 (line 3" in str(err.value)
    assert "Invalid object name" in str(err.value)
    assert db.ran == ["SELECT 1;"]


def test_the_real_sql_folder_follows_the_convention():
    found = sqlrunner.discover(find_repo_root() / "sql")
    assert found, "no SQL files discovered"
    pre = {f.rel for f in sqlrunner.select(found, "pre", "full")}
    assert {"raw/001_oscar_inyear.sql", "quarantine/001_oscar_inyear.sql"} <= pre
    # the landing tables of the raw and quarantine layers, and the typed table of the synthetic user map
    assert all(f.layer in ("raw", "quarantine", "synthetic") for f in found if f.rel in pre)
    assert {f.rel for f in found if f.layer == "synthetic"} == {
        "synthetic/820_user_department.sql",
        "synthetic/940_whatif_parameter.sql",
    } <= pre
    # everything derived runs after the loads
    post = [f.rel for f in sqlrunner.select(found, "post", "full")]
    assert (
        post.index("stg/010_inyear_snapshot.sql")
        < post.index("stg/020_release.sql")
        < post.index("audit/020_file_control.sql")
    )
