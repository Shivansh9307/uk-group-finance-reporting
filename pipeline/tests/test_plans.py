"""Plan-table reader on cells copied from the real Estimates, PESA and SR25 workbooks."""

from decimal import Decimal

import pytest
from xlsx_fixture import write_xlsx

from ukfr.profile import plans as pp
from ukfr.readers import plans as rp

N = lambda s: ("n", s)  # noqa: E731  a numeric cell as Excel stores it


@pytest.fixture
def estimates_xlsx(tmp_path):
    # 2026-27 Main Estimates, sheet RDEL: names in column B, a memo line in column C, footnote digits
    rows = [
        [None, "Table 1: Departmental Resource Budgets (Resource DEL)1"],
        [None, "£ billion", None, "Plans"],
        [None, None, None, "2026-27"],
        [None, "Resource DEL"],
        [None, "Home Office2", None, N("20.250954")],
        [None, "Business, Energy and Industrial Strategy5", None, N("16.128999999999998")],
        [None, "Scottish Government3 ", None, N("27.353898")],
        [None, None, "o/w block grant adjustments", N("-16.053623")],
        [None, "Total Resource DEL4", None, N("63.733852")],
        [None, "1 These numbers show the Resource Departmental Expenditure Limits (RDEL) budgets for 2026-27."],
    ]
    return write_xlsx(tmp_path / "2026-27_Mains_DEL_tables.xlsx", {"RDEL": rows})


@pytest.fixture
def pesa_xlsx(tmp_path):
    # PESA 2026 Table 1.3: years in row 4, outturn/plans in row 5, a section heading, '-' cells
    rows = [
        ["Table 1.3 Resource budgets, 2021-22 to 2028-29"],
        [" ", None, None, "£ million"],
        [None, "Accredited Official Statistics"],
        [None, "2024-25", "2025-26", "2026-27"],
        [None, "outturn", "outturn", "plans"],
        ["Resource DEL by departmental group"],
        ["Health and Social Care", N("193238"), N("204067"), N("212300")],
        ["Scottish Government (1)", N("24649"), N("25650"), N("27354")],
        ["Reserves", "-", "-", N("3148")],
        ["Total resource DEL", N("217887"), N("229717"), N("242802")],
        ["Resource departmental AME by departmental group"],
        ["Health and Social Care", N("21260"), N("26161"), N("30082")],
        ["(1) Within this table, the Resource DEL total for Scottish Government includes the Block Grant Adjustments."],
    ]
    return write_xlsx(tmp_path / "PESA_2026_CP_Chapter_1_tables.xlsx", {"Table_1_3": rows})


def test_excel_number_rounds_to_fifteen_digits():
    assert rp.excel_number("16.128999999999998") == Decimal("16.129")
    assert rp.excel_number("3.2717000000000001") == Decimal("3.2717")
    assert rp.excel_number("100") == Decimal("100")
    assert str(rp.excel_number("211001517.374624")) == "211001517.374624"


@pytest.mark.parametrize(
    "raw, clean",
    [
        ("Home Office2", "Home Office"),
        ("Scottish Government3 ", "Scottish Government"),
        ("Scottish Government (1), (3)", "Scottish Government"),
        ("DLUHC (1) - Housing and Communities", "DLUHC - Housing and Communities"),
        ("Total Resource DEL excluding depreciation5", "Total Resource DEL excluding depreciation"),
        ("Law Officers' Departments", "Law Officers' Departments"),
        ("Transport (excl. High Speed 2)", "Transport (excl. High Speed 2)"),
    ],
)
def test_clean_name(raw, clean):
    assert rp.clean_name(raw) == clean


def test_estimates_table(estimates_xlsx):
    (t,) = rp.read_tables(estimates_xlsx)
    assert t.unit == "£ billion" and t.years == ["2026-27"] and t.statuses == {"2026-27": "plans"}
    assert rp.estimates_measure(t.title) == "RDEL"
    lines = t.lines()
    assert [r.name for r in lines] == ["Home Office", "Business, Energy and Industrial Strategy", "Scottish Government"]
    assert lines[1].values["2026-27"] == Decimal("16.129")
    memo = [r for r in t.rows if r.kind == "memo"]
    assert [r.raw_name for r in memo] == ["o/w block grant adjustments"]
    (total,) = [r for r in t.rows if r.kind == "total"]
    assert sum(r.values["2026-27"] for r in lines) == total.values["2026-27"]
    assert rp.unit_multiplier_to_thousands(t.unit) == Decimal(1_000_000)


def test_pesa_table(pesa_xlsx):
    (t,) = rp.read_tables(pesa_xlsx)
    assert t.unit == "£ million" and t.year_row == 3 and t.status_row == 4
    assert t.statuses == {"2024-25": "outturn", "2025-26": "outturn", "2026-27": "plans"}
    rdel = t.lines("Resource DEL by departmental group")
    assert [r.name for r in rdel] == ["Health and Social Care", "Scottish Government", "Reserves"]
    assert rdel[2].values == {"2024-25": None, "2025-26": None, "2026-27": Decimal(3148)}
    ame = t.lines("Resource departmental AME")
    assert [r.name for r in ame] == ["Health and Social Care"]
    assert pp._section_measure(t.title, ame[0].section) == "RESOURCE_DEPT_AME"
    assert pp._section_measure(t.title, rdel[0].section) == "RDEL"


@pytest.mark.parametrize(
    "name, target, confidence",
    [
        ("Health and Social Care", "Health (NHS)", "high"),
        ("MHCLG Local Government", "CLG Local Government", "high"),
        ("DLUHC Levelling Up, Housing and Communities", "CLG Communities", "high"),
        ("Scottish Government", "Scotland", "high"),
        ("HM Revenue and Customs", "HM Revenue & Customs", "high"),
        ("Law Officers' Departments", "Law Officer's Departments", "high"),
        ("Transport - High Speed 27", "Transport", "high"),
        ("Single Intelligence Account", None, "none"),
        ("Business, Energy and Industrial Strategy", None, "low"),
        ("Reserves", None, "n/a"),
        ("Education", "Education", "high"),
    ],
)
def test_map_name(name, target, confidence):
    bud = [
        "Health (NHS)",
        "CLG Local Government",
        "CLG Communities",
        "Scotland",
        "HM Revenue & Customs",
        "Law Officer's Departments",
        "Transport",
        "Education",
    ]
    got, conf, _note = pp.map_name(name, bud)
    assert (got, conf) == (target, confidence)
