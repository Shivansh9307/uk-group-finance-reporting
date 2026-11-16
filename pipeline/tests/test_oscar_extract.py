"""Annual extract reader and the profiling scan, on four real lines of the 2021-22 extract."""

import zipfile
from decimal import Decimal
from pathlib import Path

import pytest

from ukfr.profile import extract as pe
from ukfr.readers import oscar_extract as rx

FIXTURE = Path(__file__).parent / "fixtures" / "extract_2021_22_head.txt"


@pytest.fixture
def extract_zip(tmp_path) -> Path:
    p = tmp_path / "2022_OSCAR_Extract_2021_22.zip"
    with zipfile.ZipFile(p, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.write(FIXTURE, "2022_OSCAR_Extract_2021_22.txt")
    return p


@pytest.mark.parametrize(
    "text, value",
    [(" 000000000005000.", Decimal(5000)), ("-000000000000336.", Decimal(-336)), (" 000000000000000.", Decimal(0))],
)
def test_parse_amount(text, value):
    assert rx.parse_amount(text) == value


def test_parse_amount_rejects_blank():
    with pytest.raises(ValueError):
        rx.parse_amount("  ")


@pytest.mark.parametrize(
    "label, period",
    [("Period 0 - 17-18", 0), ("Apr-17", 1), ("Dec-21", 9), ("Mar-22", 12), ("Period 13 - 21-22", 13)],
)
def test_month_period(label, period):
    assert rx.month_period(label) == period


def test_month_period_rejects_unknown():
    with pytest.raises(ValueError):
        rx.month_period("P01")


def test_control_budget_detail_uses_in_year_spelling():
    assert rx.control_budget_detail("DEPARTMENTAL EXPENDITURE LIMITS PROGRAMME") == "DEL PROG"
    assert rx.control_budget_detail("NON-BUDGET (NB)") == "NON-BUDGET"


def test_open_extract_reads_header_and_rows(extract_zip):
    with rx.open_extract(extract_zip) as (header, ix, rows):
        rows = list(rows)
    assert len(header) == rx.N_COLUMNS
    assert all(len(r) == rx.N_COLUMNS for r in rows)
    assert [r[ix["VERSION_CODE"]] for r in rows] == ["PLANS", "R13", "R13"]
    assert [rx.month_period(r[ix["MONTH_SHORT_NAME"]]) for r in rows] == [0, 1, 12]
    assert sum(rx.parse_amount(r[ix["AMOUNT"]]) for r in rows) == Decimal(-14422080)


def test_check_header_rejects_missing_column():
    with pytest.raises(ValueError):
        rx.check_header(["A"] * rx.N_COLUMNS)


def test_chunk_reader_handles_large_chunks():
    # one inflated chunk much larger than the read buffer must not be re-sliced per read
    data = b"x" * (5 << 20) + b"\n" + b"y\n"
    with rx.text_stream(iter([data[:3], data[3:]]), encoding="ascii") as t:
        lines = t.readlines()
    assert len(lines) == 2 and lines[1] == "y\n"


def test_scan_counts_every_row_and_sums_exactly(extract_zip):
    s = pe.scan_extract(extract_zip)
    assert s["rows"] == 3 and s["bad_width"] == 0
    assert s["vrows"] == {"PLANS": 1, "R13": 2}
    assert s["amount_total"] == sum((a for _n, a in s["cube"].values()), Decimal(0))
    assert sum(n for n, _a in s["cube"].values()) == 3
    assert pe.fiscal_year(s) == "2021-22"
    # the organisation of each row is mapped to its department group
    assert {g for (_o, g) in s["org_group"]} == {"MOD017.GROUP", "WAG090.GROUP", "SCT075.GROUP"}


def test_version_order():
    assert sorted(["R13", "R2", "PLANS", "R10"], key=pe.version_order) == ["PLANS", "R2", "R10", "R13"]


def test_fmt_has_no_exponent():
    assert pe.fmt(Decimal("5E+3")) == "5000"
    assert pe.fmt(Decimal("-0.50")) == "-0.5"
    assert pe.fmt(None) == ""
