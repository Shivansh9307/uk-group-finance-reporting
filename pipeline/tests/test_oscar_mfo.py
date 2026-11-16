"""MFO reader on real lines of MFO-R05-2022-23.csv: the header, one ordinary record and the record
that a stray line break splits after its first field."""

import zipfile
from decimal import Decimal
from pathlib import Path

import pytest

from ukfr.profile import mfo as pm
from ukfr.readers import oscar_mfo as rm

FIXTURE = Path(__file__).parent / "fixtures" / "mfo_r05_2022_23_split_record.csv"


@pytest.fixture
def mfo_zip(tmp_path) -> Path:
    p = tmp_path / "MFO_2022-23_New.zip"
    with zipfile.ZipFile(p, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.write(FIXTURE, "MFO-R05-2022-23.csv")
    return p


@pytest.mark.parametrize(
    "name, expected",
    [
        ("MFO-R01-2021-22.csv", (1, "2021-22")),
        ("MFO-R09-202223.csv", (9, "2022-23")),
        ("MFO-R00-2022-23.csv", (0, "2022-23")),
    ],
)
def test_parse_member(name, expected):
    assert rm.parse_member(name) == expected


def test_parse_period():
    assert rm.parse_period("P01") == 1 and rm.parse_period("P12") == 12
    with pytest.raises(ValueError):
        rm.parse_period("Apr-21")


def test_control_budget_detail_either_way_round():
    assert rm.control_budget_detail("DEPT AME", "AME") == "DEPT AME"
    assert rm.control_budget_detail("DEPARTMENTAL EXPENDITURE LIMITS ADMINISTRATION", "x") == "DEL ADMIN"


def test_split_record_is_rejoined(mfo_zip):
    stats = rm.RepairStats()
    with rm.open_return(mfo_zip, "MFO-R05-2022-23.csv", stats) as (header, ix, rows):
        rows = list(rows)
    assert len(header) == 91
    assert all(len(r) == 91 for r in rows)
    assert len(rows) == 3
    assert stats.joined == [4]  # record 4 (header is record 1) was a line holding only "202223"
    assert rows[-1][ix["YEAR_NO"]] == "202223"
    assert [rm.parse_period(r[ix["MONTH_SHORT_NAME"]]) for r in rows] == [1, 10, 10]


def test_repair_leaves_other_short_rows_alone():
    rows = [["a"] * 3, ["only"], ["b"] * 3, ["x", "y"]]
    out = list(rm.repair_split_rows(iter(rows), 3, rm.RepairStats()))
    assert out == rows


def test_scan_return_totals(mfo_zip):
    r = pm.scan_return(mfo_zip, "MFO-R05-2022-23.csv")
    assert r["return"] == 5 and r["fy"] == "2022-23"
    assert r["rows"] == 3 and r["bad_width"] == 0 and r["joined_rows"] == [4]
    assert r["amount_total"] == sum((a for _n, a in r["cube"].values()), Decimal(0))


def test_accuracy_flags_missing_and_scale_errors():
    # one year, two groups; return 1 misses group B and states group A in pounds, not thousands
    cube = {}

    def put(ret, g, a):
        cube[("2020-21", "extract", ret, 1, g, "DEL PROG", "RESOURCE")] = Decimal(a)

    put(13, "A", 2_000_000)
    put(13, "B", 1_000_000)
    put(1, "A", 2_000_000_000)
    put(2, "A", 1_900_000)
    put(2, "B", 1_100_000)
    rows = {(r[2], r[3]): r for r in pm.accuracy(cube)}
    r1 = rows[("RDEL", 1)]
    assert r1[11] == "B" and r1[12] == "A"
    r2 = rows[("RDEL", 2)]
    assert r2[6] == Decimal(0)  # 3.0m forecast against 3.0m final
    assert r2[9] == Decimal("6.67")  # WAPE: (0.1m + 0.1m) / 3.0m
