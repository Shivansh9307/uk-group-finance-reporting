"""The authored-CSV load stage: file checks without a database, then a real load against it."""

from __future__ import annotations

import pytest

from ukfr.stages import StageContext, all_stages, select_stages
from ukfr.stages.authored import (
    AuthoredFileError,
    create_sql,
    description,
    list_authored_files,
    read_authored,
    run,
)


def write(tmp_path, name, text, encoding="utf-8"):
    folder = tmp_path / "authored"
    folder.mkdir(exist_ok=True)
    path = folder / name
    path.write_bytes(text.encode(encoding))
    return path


def test_the_stage_is_registered_with_committed_scope_and_runs_before_the_sql_loads():
    by_name = {s.name: s for s in all_stages()}
    assert by_name["authored"].scope == "committed"
    assert "authored" in [s.name for s in select_stages("committed")]
    assert by_name["authored"].order < by_name["oscar_inyear"].order


def test_a_missing_folder_means_no_files(tmp_path):
    assert list_authored_files(tmp_path) == []


def test_only_csv_files_are_listed_in_name_order(tmp_path):
    write(tmp_path, "b.csv", "x\n")
    write(tmp_path, "a.csv", "x\n")
    write(tmp_path, "README.md", "not data")
    assert [p.name for p in list_authored_files(tmp_path)] == ["a.csv", "b.csv"]


def test_header_and_rows_are_read_exactly_as_written(tmp_path):
    path = write(tmp_path, "t.csv", '﻿id,note,evidence\n1,"a, ""quoted"" value",\n\n2,,"x\ny"\n')
    header, rows = read_authored(path)
    assert header == ["id", "note", "evidence"]
    assert rows == [["1", 'a, "quoted" value', ""], ["2", "", "x\ny"]]


@pytest.mark.parametrize(
    "name, text, message",
    [
        ("t.csv", "", "empty"),
        ("t.csv", "a,a\n1,2\n", "twice"),
        ("t.csv", "a,A\n1,2\n", "twice"),
        ("t.csv", "a,_load_order\n1,2\n", "reserved"),
        ("t.csv", "a,b c\n1,2\n", "plain identifier"),
        ("t.csv", "a,1b\n1,2\n", "plain identifier"),
        ("t.csv", "a,b\n1\n", "line 2 has 1 fields"),
        ("t.csv", "a,b\n1,2,3\n", "line 2 has 3 fields"),
        ("Bad Name.csv", "a\n1\n", "file name"),
    ],
)
def test_a_bad_file_stops_the_build_with_its_name_and_the_problem(tmp_path, name, text, message):
    path = write(tmp_path, name, text)
    with pytest.raises(AuthoredFileError, match=message) as err:
        read_authored(path)
    assert path.name in str(err.value)


def test_the_table_is_all_text_with_a_load_order_and_quoted_names():
    sql = create_sql("zz", ["a", "select"])
    assert "authored.[zz]" in sql
    assert "_load_order int NOT NULL" in sql
    assert sql.count("nvarchar(max) NOT NULL") == 2
    assert "[select]" in sql


def test_the_description_says_authored():
    assert description("zz").startswith("AUTHORED")


@pytest.mark.db
def test_a_file_is_loaded_into_authored_with_text_columns_and_a_description(db, tmp_path):
    write(
        tmp_path,
        "zz_unit_test.csv",
        'id,name,evidence\n1,"Café, with ""quotes""",\n2,,"line one\nline two"\n3,£ sign,e\n',
    )
    ctx = StageContext(tmp_path, db, "committed", log=lambda s: None)
    try:
        assert run(ctx) == {"zz_unit_test": 3}
        assert run(ctx) == {"zz_unit_test": 3}  # a second run rebuilds the table, it does not add to it
        rows = db.query("SELECT _load_order, id, name, evidence FROM authored.zz_unit_test ORDER BY _load_order")
        assert rows == [
            (1, "1", 'Café, with "quotes"', ""),
            (2, "2", "", "line one\nline two"),
            (3, "3", "£ sign", "e"),
        ]
        types = db.query(
            "SELECT c.name, t.name, c.max_length, c.is_nullable FROM sys.columns c "
            "JOIN sys.types t ON t.user_type_id = c.user_type_id "
            "WHERE c.object_id = OBJECT_ID(N'authored.zz_unit_test') ORDER BY c.column_id"
        )
        assert [(n, t) for n, t, *_ in types] == [
            ("_load_order", "int"),
            ("id", "nvarchar"),
            ("name", "nvarchar"),
            ("evidence", "nvarchar"),
        ]
        text = db.scalar(
            "SELECT CAST(value AS nvarchar(400)) FROM sys.extended_properties "
            "WHERE major_id = OBJECT_ID(N'authored.zz_unit_test') AND minor_id = 0 AND name = N'MS_Description'"
        )
        assert text.startswith("AUTHORED") and "zz_unit_test.csv" in text
    finally:
        db.execute("DROP TABLE IF EXISTS authored.zz_unit_test;")


@pytest.mark.db
def test_the_committed_authored_files_are_all_loaded(db, repo_root):
    for path in list_authored_files(repo_root):
        header, rows = read_authored(path)
        n = db.scalar(f"SELECT COUNT(*) FROM authored.[{path.stem}]")
        assert n == len(rows), f"{path.name}: {n} rows in the database, {len(rows)} in the file"
        columns = [
            r[0]
            for r in db.query(
                f"SELECT name FROM sys.columns WHERE object_id = OBJECT_ID(N'authored.{path.stem}') ORDER BY column_id"
            )
        ]
        assert columns == ["_load_order", *header]
