"""Fixtures for tests that need the built SQL Server database (marker `db`).

The tests read a database that `ukfr build` has already filled; they never build one. Which database
comes from the same environment variables the build uses (`UKFR_SQL_*`). When no server answers, or
the database has not been built, the tests are skipped, unless `UKFR_REQUIRE_DB=1` is set (CI sets
it), in which case they fail.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from ukfr.config import data_dir, find_repo_root
from ukfr.db import Db, DbSettings

REQUIRE = "UKFR_REQUIRE_DB"


def _unavailable(reason: str):
    if os.environ.get(REQUIRE) == "1":
        pytest.fail(f"database tests are required ({REQUIRE}=1) but {reason}", pytrace=False)
    pytest.skip(reason)


@pytest.fixture(scope="session")
def repo_root() -> Path:
    return find_repo_root()


@pytest.fixture(scope="session")
def db_settings() -> DbSettings:
    return DbSettings.from_env()


@pytest.fixture(scope="session")
def db(db_settings):
    try:
        conn = Db(db_settings, login_timeout=10)
    except Exception as exc:
        _unavailable(f"cannot connect to {db_settings.describe()}: {type(exc).__name__}")
    try:
        built = conn.scalar("SELECT OBJECT_ID(N'audit.file_control')")
    except Exception as exc:
        conn.close()
        _unavailable(f"cannot query {db_settings.describe()}: {type(exc).__name__}")
    if built is None:
        conn.close()
        _unavailable(f"{db_settings.database} has not been built (run `ukfr build`)")
    yield conn
    conn.close()


def pytest_configure(config):
    """Register the markers here so they exist whichever folder pytest is started from."""
    config.addinivalue_line(
        "markers",
        "db: needs the SQL Server database built by `ukfr build` (skipped when it is not there; "
        "CI sets UKFR_REQUIRE_DB=1 so a skip becomes a failure)",
    )
    config.addinivalue_line(
        "markers", "localdata: needs source files that are not in git (under UKFR_DATA_DIR); skipped when absent"
    )


def pytest_collection_modifyitems(config, items):
    """Skip `localdata` tests when there is no data directory with files in it."""
    root = find_repo_root()
    raw = data_dir(root)
    present = raw.is_dir() and any(raw.iterdir())
    skip = pytest.mark.skip(reason=f"no local source files under {raw}")
    for item in items:
        if "localdata" in item.keywords and not present:
            item.add_marker(skip)
