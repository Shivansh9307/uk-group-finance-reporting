"""ukfr.readers.oscar_inyear on snippets cut from each published header layout (no network, no data dir)."""

from __future__ import annotations

from decimal import Decimal

import pytest
from oscar_snippets import V2019_JUN19, V2019_SEP19, V2021DEC, V2021SEP, V2023_SEP26, ods_mar26

from ukfr.readers.oscar_inyear import (
    InyearFormatError,
    ReadStats,
    detect_variant,
    parse_amount,
    parse_month,
    parse_quarter,
    read_inyear_bytes,
)


def read(data: bytes, release: str, kind: str = "csv"):
    stats = ReadStats()
    rows = list(read_inyear_bytes(data, release, kind, stats))
    return rows, stats


def test_v2019_layout_thousands_separator_cp1252_and_blank_rows():
    rows, stats = read(V2019_JUN19, "2019-06")
    assert stats.header_variant == "v2019"
    assert (stats.total_rows, stats.blank_rows, stats.blank_rows_trailing, stats.data_rows) == (5, 2, 2, 3)
    assert [r.amount for r in rows] == [Decimal("2394"), Decimal("2871"), Decimal("-8")]
    assert stats.amount_forms == {"thousands_separator": 2, "plain": 1}
    assert rows[1].sub_segment_name.endswith("Government’s programme and the Prime Minister’s priorities.")
    assert stats.high_byte_values == "92" and stats.utf8_valid is False
    assert rows[0].pesa_economic_group_name == "Staff costs"
    assert (rows[0].financial_year, rows[0].period, rows[0].release) == ("2018-19", 1, "2019-06")


def test_period_zero_is_kept_and_flagged_not_dropped():
    rows, stats = read(V2019_JUN19, "2019-06")
    p0 = rows[2]
    assert (p0.month, p0.quarter, p0.financial_year, p0.period) == ("Period 0 - 18-19", "Period 0 - 18-19", "", 0)
    assert stats.month_unparsed == 1


def test_line_break_inside_quoted_field_is_one_record():
    rows, stats = read(V2019_SEP19, "2019-09")
    assert len(rows) == 1 and stats.bare_lf == 1
    assert rows[0].sub_segment_name == "X004D388-East West Rai Ltd (ALB) DEL Admin Voted"
    assert stats.stripped_fields == 1


def test_v2021sep_and_v2021dec_layouts_map_to_the_same_columns():
    sep, s1 = read(V2021SEP, "2021-09")
    dec, s2 = read(V2021DEC, "2021-12")
    assert (s1.header_variant, s2.header_variant) == ("v2021sep", "v2021dec")
    same = ("organisation_code", "sub_segment_code", "economic_category_code", "control_budget_detail_code", "amount")
    assert [getattr(sep[1], c) for c in same] == [getattr(dec[0], c) for c in same]
    assert sep[0].version == "MFO_202122_R04_PSF_v6" and sep[0].amount == 0
    assert dec[0].control_budget_code == "DEL" and dec[0].pesa_economic_group_name == ""
    assert (dec[0].financial_year, dec[0].period) == ("2021-22", 6)


def test_v2023_layout_scientific_and_decimals_are_exact():
    rows, stats = read(V2023_SEP26, "2026-09")
    assert stats.header_variant == "v2023"
    assert [r.amount for r in rows] == [Decimal("2"), Decimal("87"), Decimal("-0.0000833"), Decimal("-6.62978")]
    assert stats.amount_forms == {"plain": 3, "scientific": 1}
    assert "–" in rows[0].sub_segment_name and " " in rows[1].sub_segment_name
    assert stats.high_byte_values == "96 A0"


def test_ods_reads_the_data_sheet_skips_the_pivot_and_counts_trailing_blanks():
    rows, stats = read(ods_mar26(), "2026-03", "ods")
    assert stats.sheet == "OSCAR_in_year_dataset_Mar_2025" and stats.other_sheets == ["Pivot"]
    assert stats.data_rows == 3 and stats.blank_rows_trailing == 1048000
    assert rows[2].amount == Decimal("-0.070069999999999993")  # the exact text of office:value
    assert stats.amount_forms == {"ods_float_plain": 2, "ods_float_scientific": 1}
    assert rows[2].sub_segment_code == "X047A134" and rows[2].period == 6


def test_ods_rows_compressed_by_the_writer_are_expanded():
    rows, stats = read(ods_mar26(repeat_first_row=3), "2026-03", "ods")
    assert stats.data_rows == 5
    assert rows[0][2:] == rows[1][2:] == rows[2][2:]


def test_unknown_header_fails_loudly():
    bad = V2023_SEP26.replace(b"Economic Budget Code", b"Economic Budget Kode", 1)
    with pytest.raises(InyearFormatError, match="unknown header"):
        read(bad, "2026-09")
    with pytest.raises(InyearFormatError, match="unknown header"):
        detect_variant(["Organisation Code", "Amount"], "test")


def test_extra_populated_column_fails():
    bad = V2021DEC.replace(b"Sep-21,138\r\n", b"Sep-21,138,surprise\r\n")
    with pytest.raises(InyearFormatError, match="17 fields"):
        read(bad, "2021-12")


def test_undecodable_byte_fails():
    bad = V2023_SEP26.replace(b"\x96", b"\x81")  # 0x81 is undefined in Windows-1252
    with pytest.raises(InyearFormatError, match="cp1252"):
        read(bad, "2026-09")


@pytest.mark.parametrize(
    "text,value,form",
    [
        ("123", "123", "plain"),
        ("-1.49794", "-1.49794", "plain"),
        ("1,234,567", "1234567", "thousands_separator"),
        ("-31,845", "-31845", "thousands_separator"),
        ("-1.06581E-14", "-1.06581E-14", "scientific"),
        ("(1,234)", "-1234", "parentheses"),
        ("45-", "-45", "trailing_minus"),
        (" 7 ", "7", "plain"),
    ],
)
def test_amount_forms(text, value, form):
    v, f = parse_amount(text)
    assert v == Decimal(value) and f == form


def test_blank_amount_is_none_and_garbage_fails():
    assert parse_amount("  ") == (None, "blank")
    for bad in ("1,23", "12a", "--1", "1.2.3", "£5"):
        with pytest.raises(InyearFormatError):
            parse_amount(bad)


def test_months_quarters():
    assert parse_month("Apr-22") == ("2022-23", 1)
    assert parse_month("Mar-23") == ("2022-23", 12)
    assert parse_month("Jan-19") == ("2018-19", 10)
    assert parse_month("Period 0 - 18-19") == ("", 0)
    assert parse_quarter("Qtr1 - 21-22") == (1, "2021-22")
    assert parse_quarter("Period 0 - 18-19") == (0, "")
