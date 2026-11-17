"""Run every invariant under `sql/tests/` against the built database.

Each file is one query that returns the rows that break the invariant, so zero rows is a pass. The
first lines carry `-- test: <what must hold>`; a check that reads data that is not in git adds
`-- marker: localdata` and is skipped when `$UKFR_DATA_DIR` has no files. Adding a check means adding a
file; this module collects it by scanning the folder.
"""

from __future__ import annotations

import pytest

from ukfr import sqlrunner
from ukfr.config import find_repo_root

SQL_DIR = find_repo_root() / "sql"
FILES = sqlrunner.collect_test_files(SQL_DIR)


def test_the_sql_tests_folder_is_not_empty():
    assert FILES, f"no .sql files under {SQL_DIR / 'tests'}"


def _param(path):
    marks = [pytest.mark.db]
    if sqlrunner.header_directives(path.read_text(encoding="utf-8")).get("marker") == "localdata":
        marks.append(pytest.mark.localdata)
    return pytest.param(path, marks=marks, id=path.relative_to(SQL_DIR / "tests").as_posix())


@pytest.mark.parametrize("path", [_param(p) for p in FILES])
def test_invariant(db, path):
    text = path.read_text(encoding="utf-8")
    d = sqlrunner.header_directives(text)
    assert "test" in d, f"{path.name} needs a '-- test: ...' line near the top"
    assert len(sqlrunner.split_batches(text)) == 1, f"{path.name}: a test is one batch (no GO)"
    rows = db.query(text)
    shown = "\n".join(repr(r) for r in rows[:10])
    assert not rows, f"{d['test']}\n{len(rows)} offending row(s), first {min(len(rows), 10)}:\n{shown}"
