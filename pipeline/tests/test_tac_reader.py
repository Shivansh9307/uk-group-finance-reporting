"""The TAC reader on small workbooks written to look like the published ones (no database, no real files)."""

from __future__ import annotations

from decimal import Decimal

import pytest
from xlsx_fixture import write_xlsx

from ukfr.readers import tac as rt


def num(text: str) -> tuple[str, str]:
    return ("n", text)


HEADER_2425 = ["OrganisationName", "WorkSheetName", "TableID", "MainCode", "RowNumber", "SubCode", "Total"]
HEADER_1920 = ["Organisation Name", "WorkSheetName", "TableID", "MainCode", "RowNumber", "SubCode", "Value number"]


def data_rows(header):
    return [
        header,
        ["Alpha NHS Trust", "TAC02 SoCI", num("1"), "A02CY01", num("12"), "SCI0100A", num("376880")],
        ["Alpha NHS Trust", "TAC03 SoFP", num("1"), "A03PY01", num("44"), "BAL1400", num("-9673.779330000001")],
        ["Alpha NHS Trust", "TAC06 Op Inc 1", num("1"), "A06CY01", num("10"), "OIN0100", num("5")],
        [],
        ["Beta NHS Trust", "TAC05 SoCF", num("1"), "A05CY01", num("31"), "SCF0180", num("0")],
    ]


def make(tmp_path, header, name="TAC-data-published-in-NHS-trusts-accounts-for-2024-25.xlsx"):
    path = write_xlsx(
        tmp_path / name,
        {
            "Intro": [[None, "NHS England - 2024/25 TAC data set"], [None], [None, "Second line"]],
            "List of providers": [
                ["Full name of Provider", "NHS code", "Region", "Sector", "Comments "],
                ["Alpha NHS Trust", "R01", "London", "Acute", None],
                ["Beta NHS Trust", "R02", "London", "Acute", "Acquired by Alpha NHS Trust (R01) on 1 April 2025"],
            ],
            "All data": data_rows(header),
        },
    )
    return rt.TacFile("2024-25", path.name, path.name, "0" * 64)


@pytest.mark.parametrize("header", [HEADER_2425, HEADER_1920])
def test_both_header_spellings_load_the_statement_rows_and_count_the_rest(tmp_path, header):
    f = make(tmp_path, header)
    stats = rt.TacStats()
    rows = list(rt.read_data(f, tmp_path, stats))
    assert [r.values[1] for r in rows] == ["TAC02 SoCI", "TAC03 SoFP", "TAC05 SoCF"]
    assert [r.line for r in rows] == [2, 3, 6]
    assert rows[0].values == ("Alpha NHS Trust", "TAC02 SoCI", "1", "A02CY01", "12", "SCI0100A", "376880")
    assert rows[0].amount == Decimal("376880")
    assert stats.data_rows == 4 and stats.blank_rows == 1 and stats.statement_rows == 3
    assert stats.worksheet_rows["TAC06 Op Inc 1"] == 1


def test_a_float_artefact_is_rounded_to_the_value_the_cell_shows(tmp_path):
    f = make(tmp_path, HEADER_2425)
    rows = list(rt.read_data(f, tmp_path))
    assert rows[1].amount == Decimal("-9673.77933")
    assert rows[1].values[-1] == "-9673.77933"


def test_an_unknown_header_stops_the_load(tmp_path):
    f = make(tmp_path, HEADER_2425[:-1] + ["Amount"])
    with pytest.raises(rt.TacFormatError, match="unknown header"):
        list(rt.read_data(f, tmp_path))


def test_a_non_numeric_value_stops_the_load(tmp_path):
    header = HEADER_2425
    path = write_xlsx(
        tmp_path / "TAC-data-published-in-NHS-trusts-accounts-for-2024-25.xlsx",
        {"All data": [header, ["A", "TAC02 SoCI", num("1"), "A02CY01", num("12"), "SCI0100A", "n/a"]]},
    )
    f = rt.TacFile("2024-25", path.name, path.name, "0" * 64)
    with pytest.raises(rt.TacFormatError, match="not a number"):
        list(rt.read_data(f, tmp_path))


def test_a_worksheet_that_is_not_a_form_stops_the_load(tmp_path):
    path = write_xlsx(
        tmp_path / "TAC-data-published-in-NHS-trusts-accounts-for-2024-25.xlsx",
        {"All data": [HEADER_2425, ["A", "Sheet1", num("1"), "A02CY01", num("12"), "SCI0100A", num("1")]]},
    )
    f = rt.TacFile("2024-25", path.name, path.name, "0" * 64)
    with pytest.raises(rt.TacFormatError, match="does not start with a TAC form code"):
        list(rt.read_data(f, tmp_path))


def test_the_provider_list_and_intro_are_read(tmp_path):
    f = make(tmp_path, HEADER_2425)
    providers = rt.read_providers(f, tmp_path)
    assert [p.values[:2] for p in providers] == [("Alpha NHS Trust", "R01"), ("Beta NHS Trust", "R02")]
    assert providers[1].values[5].startswith("Acquired by Alpha")
    assert providers[0].values[2] == ""  # no authorisation date column in a trust file
    assert rt.read_intro(f, tmp_path) == [(1, "NHS England - 2024/25 TAC data set"), (3, "Second line")]


def test_the_file_kind_and_provider_type_come_from_the_name():
    trust = rt.TacFile("2024-25", "TAC-data-published-in-NHS-trusts-accounts-for-2024-25.xlsx", "", "")
    ft = rt.TacFile("2020-21", "TAC-data-published-in-NHS-foundation-trust-accounts-for-2020-21.xlsx", "", "")
    form = rt.TacFile("2021-22", "2021-22-NHS-provider-TAC-ilustrative-file.xlsx", "", "")
    assert (trust.kind, trust.provider_type) == ("data", "NHS trust")
    assert (ft.kind, ft.provider_type) == ("data", "NHS foundation trust")
    assert (form.kind, form.provider_type) == ("template", "")


def test_the_template_gives_line_text_sign_and_sub_code(tmp_path):
    sheet = lambda code, title, mc, lines: [  # noqa: E731
        [],
        [None, "NHS England"],
        [None, code],
        [None, "Trust Accounts Consolidation Schedules"],
        [None, None, None, None, None, "Table ID", "1"],
        [None, title, None, None, mc[0], mc[1], "Maincode"],
        [None, None, None, "Expected sign", "x", "x"],
        *lines,
    ]
    path = write_xlsx(
        tmp_path / "2024-25-NHS-Provider-TAC-illustrative-file.xlsx",
        {
            "Intro": [[None, "x"]],
            "TAC02 SoCI": sheet(
                "TAC02 SoCI", "STATEMENT OF COMPREHENSIVE INCOME", ("A02CY01", "A02PY01"),
                [[None, "Operating income", None, "+", num("0"), num("0"), "SCI0100A"]],
            ),
            "TAC03 SoFP": sheet(
                "TAC03 SoFP", "STATEMENT OF FINANCIAL POSITION", ("A03CY01", "A03PY01"),
                [[None, "Non-current assets"], [None, "Intangible assets", "+", num("0"), num("0"), "BAL1100"]],
            ),
            "TAC05 SoCF": sheet(
                "TAC05 SoCF", "STATEMENT OF CASH FLOWS", ("A05CY01", "A05PY01"),
                [[None, "Net cash", None, "+/-", num("0"), num("0"), "SCF0180"]],
            ),
            "TAC06 Op Inc 1": [[None, "ignored"]],
        },
    )  # fmt: skip
    f = rt.TacFile("2024-25", path.name, path.name, "")
    rows = rt.read_template(f, tmp_path)
    assert [(r.worksheet, r.label, r.expected_sign, r.sub_code) for r in rows] == [
        ("TAC02 SoCI", "Operating income", "+", "SCI0100A"),
        ("TAC03 SoFP", "Non-current assets", "", ""),
        ("TAC03 SoFP", "Intangible assets", "+", "BAL1100"),
        ("TAC05 SoCF", "Net cash", "+/-", "SCF0180"),
    ]
    assert rows[0].table_id == "1" and (rows[0].main_cy, rows[0].main_py) == ("A02CY01", "A02PY01")
