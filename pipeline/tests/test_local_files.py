"""Checks that need the large source files kept outside git (marker `localdata`, skipped without them)."""

from __future__ import annotations

import pytest

from ukfr.config import load_settings
from ukfr.verify import verify


@pytest.mark.localdata
def test_every_local_raw_file_matches_its_recorded_sha256(repo_root):
    res = verify(repo_root, load_settings(repo_root))
    assert res.ok, res.failures[:5]
    assert res.raw_ok > 0
