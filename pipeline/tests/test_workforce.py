"""The workforce reader: header variants, number formats, missing Year and Month columns, and unknown headers.

The cells are copied from the shape of the real files (a one-row header with line breaks, a three-row header with
merged group cells, the older grade names); no file is read from disk except the small ones written here."""

from __future__ import annotations

from decimal import Decimal

import pytest

from ukfr.controls import workforce_independent as independent
from ukfr.readers import workforce as w

ID_ROW = ["Year", "Month", "Organisation name", "Organisation type", "Main, parent or sponsoring department:"]


def _grid_text(rows: list[list[str]]) -> str:
    import csv
    import io

    buf = io.StringIO()
    csv.writer(buf, lineterminator="\n").writerows(rows)
    return buf.getvalue()


def _read(path, fmt="csv"):
    stats = w.WorkforceStats()
    grids = w.read_grids(path, fmt)
    _, rows = w.pick_sheet(grids, path.name)
    return list(w.read_sheet(rows, path.name, stats)), stats


@pytest.mark.parametrize(
    ("label", "key"),
    [
        ("Payroll staff;\nAO/AA;\nHeadcount", "payroll_ao_aa_hc"),
        ("Payroll Staff; AO/AA; Full-Time Equivalent", "payroll_ao_aa_fte"),
        ("Payroll Staff, Total; Full-Time Equivalent", "payroll_total_fte"),
        ("Payroll staff Admin officers/admin assistants Headcount", "payroll_ao_aa_hc"),
        (
            "Payroll staff Higher Executive Officers/Senior Executive Officers Full-time equivalent",
            "payroll_seo_heo_fte",
        ),
        ("Payroll staff Other, unknown, or unspecified Headcount", "payroll_other_hc"),
        ("Payroll staff Total Employees Full-time equivalent", "payroll_total_fte"),
        (
            "Non-payroll staff; Interim Managers & Specialist Contractors & Medical; Headcount",
            "np_interim_specialist_hc",
        ),
        ("Non-payroll staff, Total Contingent labour, Full-Time Equivalent", "np_contingent_total_fte"),
        ("Non-payroll staff; Consultancy; Number of Contracts", "np_consultancy_contracts_n"),
        (
            "Number of non-payroll staff (contingent labour and consultants/consultancy) Agency staff Headcount",
            "np_agency_hc",
        ),
        (
            "Number of non-payroll staff (contingent labour and consultants/consultancy) Total Full-time equivalent",
            "np_total_fte",
        ),
        ("Grand Total (workforce numbers); Full-time equivalent", "grand_total_fte"),
        ("Payroll staff costs; Employer national insurance contributions", "cost_employer_ni_gbp"),
        ("Payroll staff costs Total paybill for payroll staff", "cost_payroll_paybill_gbp"),
        ("Non-Payroll staff costs; Contingent labour", "cost_contingent_gbp"),
        ("Non-Payroll staff (contingent labour/consultancy) costs Total monthly cost of consultants/ consultancy",
         "cost_consultancy_gbp"),
        ("Non-Payroll staff costs; Total staff costs", "cost_non_payroll_total_gbp"),
        ("Grand Total paybill/staffing (payroll and non-payroll) costs", "cost_grand_total_gbp"),
    ],
)
def test_the_wordings_the_files_use_read_as_one_key(label, key):
    assert w.measure_key(w.normalise(label)) == key


def test_a_label_the_reader_does_not_know_has_no_key():
    assert w.measure_key(w.normalise("Payroll staff; Apprentices; Headcount")) is None
    assert w.measure_key(w.normalise("Grand Total (workforce numbers); Cost")) is None


@pytest.mark.parametrize(
    ("text", "number"),
    [
        ("£1,877,791.41", Decimal("1877791.41")),
        ("-£3,066.35", Decimal("-3066.35")),
        ("£-3,066.35", Decimal("-3066.35")),
        ("(12.5)", Decimal("-12.5")),
        ("7,500", Decimal("7500")),
        ("0.00", Decimal("0.00")),
        (" 102.45837837837838 ", Decimal("102.4584")),  # 4 decimal places
        ("2.27e-13", None),  # an exponent is not a number I accept in a text cell
        ("0.00004", Decimal("0")),  # below 5e-5 is a spreadsheet residue
        (".", None),
        ("n/a", None),
        ("", None),
        ("1.2.3", None),
    ],
)
def test_numbers_are_read_exactly_or_not_at_all(text, number):
    assert w.parse_number(text) == number
    assert independent._number(text) == number or (number is None and independent._number(text) is None)


def test_one_row_header_with_line_breaks_pound_signs_and_a_blank_cell(tmp_path):
    header = [
        *ID_ROW,
        "Payroll staff;\nTotal;\nHeadcount",
        "Payroll staff;\nTotal;\nFull-time equivalent",
        "Payroll staff costs;\nTotal paybill",
        "Comments",
    ]
    p = tmp_path / "a.csv"
    p.write_text(
        _grid_text(
            [
                header,
                ["2026", "March", " Foo  Agency ", "Executive Agency", "Foo", "7,618", "7,500", "£48,998,253.78", ""],
                ["2026", "March", "Bar", "Other", "Foo", "", "12.5", "£0.00", "x"],
                [],
                ["", "", ""],
            ]
        ),
        encoding="utf-8-sig",
    )
    rows, stats = _read(p)
    assert stats.template == "single_row" and stats.data_rows == 2 and stats.blank_rows == 2
    first, second = rows
    assert first.organisation_name == "Foo Agency" and (first.year, first.month) == ("2026", "March")
    assert {v.key: v.number for v in first.values} == {
        "payroll_total_hc": Decimal("7618"),
        "payroll_total_fte": Decimal("7500"),
        "cost_payroll_paybill_gbp": Decimal("48998253.78"),
    }
    assert {v.key for v in second.values} == {"payroll_total_fte", "cost_payroll_paybill_gbp"}  # a blank has no value


def test_three_row_header_with_merged_group_cells_and_no_year_or_month_columns(tmp_path):
    g = [
        ["Jun-19", "", "", "", "", ""],
        ["Organisation name", "Organisation type", "Main, parent or sponsoring department:", "Payroll staff", "", ""],
        ["", "", "", "AO/AA", "", "Total\nEmployees"],
        ["", "", "", "Headcount", "Full-time\nequivalent", "Headcount"],
        ["Dept", "Ministerial Department", "Dept", "10", "9.5", "12"],
    ]
    p = tmp_path / "old.csv"
    p.write_text(_grid_text(g), encoding="utf-8")
    rows, stats = _read(p)
    assert stats.template == "multi_row" and stats.header_rows == 3 and stats.header_line == 2
    assert [(c.index, c.key) for c in stats.columns if c.index >= 3] == [
        (3, "payroll_ao_aa_hc"),
        (4, "payroll_ao_aa_fte"),
        (5, "payroll_total_hc"),
    ]
    assert rows[0].year == "" and rows[0].month == "" and rows[0].organisation_name == "Dept"


def test_a_cell_that_is_not_a_number_comes_back_without_a_number(tmp_path):
    header = [*ID_ROW, "Payroll staff;\nTotal;\nFull-time equivalent"]
    p = tmp_path / "b.csv"
    data = [["2026", "May", "B", "t", "P", "3"], ["2026", "May", "A", "t", "P", "."]]
    p.write_text(_grid_text([header, *data]), "utf-8")
    rows, _ = _read(p)
    assert [(v.text, v.number) for r in rows for v in r.values] == [("3", Decimal("3")), (".", None)]


def test_an_unknown_header_fails_loudly_and_names_the_column(tmp_path):
    header = [*ID_ROW, "Payroll staff;\nApprentices;\nHeadcount"]
    p = tmp_path / "c.csv"
    p.write_text(_grid_text([header, ["2026", "May", "A", "t", "P", "1"]]), "utf-8")
    with pytest.raises(w.WorkforceFormatError, match="unknown header in column 6"):
        _read(p)


def test_two_columns_that_read_as_one_key_fail(tmp_path):
    header = [*ID_ROW, "Payroll staff;\nTotal;\nHeadcount", "Payroll staff, Total; Headcount"]
    p = tmp_path / "d.csv"
    p.write_text(_grid_text([header, ["2026", "May", "A", "t", "P", "1", "1"]]), "utf-8")
    with pytest.raises(w.WorkforceFormatError, match="both read as"):
        _read(p)


def test_a_file_with_no_data_sheet_fails(tmp_path):
    p = tmp_path / "e.csv"
    p.write_text("a,b\n1,2\n", "utf-8")
    with pytest.raises(w.WorkforceFormatError, match="0 sheets"):
        _read(p)


def test_the_independent_control_agrees_with_the_reader_on_a_small_file(tmp_path, monkeypatch):
    header = [*ID_ROW, "Payroll staff; Total; Full-time equivalent", "Payroll staff costs; Total paybill"]
    p = tmp_path / "workforce_mi" / "x-2026-05" / "f.csv"
    p.parent.mkdir(parents=True)
    rows_in = [["2026", "May", "A", "t", "P", "1,000.25", "£10.10"], ["2026", "May", "B", "t", "P", "2", "n/a"]]
    p.write_text(_grid_text([header, *rows_in]), "utf-8")
    rows, _ = _read(p)
    by_col: dict[int, Decimal] = {}
    for r in rows:
        for v in r.values:
            if v.number is not None:
                by_col[v.column_index] = by_col.get(v.column_index, Decimal(0)) + v.number
    monkeypatch.setenv("UKFR_DATA_DIR", str(tmp_path))
    ctrl = independent.control_rows(tmp_path)
    assert ctrl == [
        ["x", "2026-05", "f.csv", "csv", "5", "2", "2", "0", "1002.25"],
        ["x", "2026-05", "f.csv", "csv", "6", "2", "1", "1", "10.1"],
    ]
    assert by_col == {5: Decimal("1002.25"), 6: Decimal("10.10")}


def _file(dept, month, name):
    return w.WorkforceFile(dept, month, f"{dept}-{month}", name, f"$UKFR_DATA_DIR/x/{name}", "0" * 64)


def test_one_primary_copy_per_month_the_fullest_then_a_spreadsheet_before_a_csv():
    from ukfr.stages.workforce import choose_primary

    files = [
        _file("a", "2024-05", "m.ods"),
        _file("a", "2024-05", "m.xlsx"),
        _file("a", "2024-05", "m.csv"),
        _file("a", "2024-06", "j.xlsx"),
        _file("a", "2024-06", "j.csv"),
        _file("a", "2024-07", "k.xls"),
        _file("a", "2024-07", "k.ods"),
        _file("b", "2024-05", "x.ods"),
    ]
    rows = {(f.release, f.filename): 10 for f in files}
    rows[("a-2024-06", "j.xlsx")] = 3  # the spreadsheet has fewer rows with a name and a value: the csv wins
    assert choose_primary(files, rows) == {
        ("a-2024-05", "m.xlsx"),
        ("a-2024-06", "j.csv"),
        ("a-2024-07", "k.xls"),
        ("b-2024-05", "x.ods"),
    }


def test_two_files_of_one_format_for_one_month_stop_the_load():
    from ukfr.stages.workforce import choose_primary

    two = [_file("a", "2024-05", "m1.csv"), _file("a", "2024-05", "m2.csv")]
    with pytest.raises(ValueError, match="two csv files for one month"):
        choose_primary(two, {(f.release, f.filename): 1 for f in two})


def test_a_release_label_that_is_not_dept_year_month_is_refused(tmp_path):
    assert w.RELEASE_RE.match("mhclg-2024-07")
    assert not w.RELEASE_RE.match("2024-07")
