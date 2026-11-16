"""GDP deflator and ONS CPI readers on rows copied from the real files."""

from decimal import Decimal
from pathlib import Path

import pytest
from xlsx_fixture import write_xlsx

from ukfr.readers import deflators as rd

N = lambda s: ("n", s)  # noqa: E731
ONS = Path(__file__).parent / "fixtures" / "ons_d7bt_snippet.csv"


@pytest.fixture
def deflator_xlsx(tmp_path):
    # October 2026 Budget vintage: column A empty, the header on row 7, forecast years carry '-'
    rows = [
        [None, "GDP DEFLATORS AT MARKET PRICES, AND MONEY GDP"],
        [],
        [None, "Forecast data are consistent with OBR EFO data as at the Budget 28 October 2026."],
        [None, "Outturn data are as at the Quarterly National Accounts from ONS - last updated 30 September 2026."],
        [None, "Financial year", None, None, None, None, None, "Calendar year"],
        [None, None, "GDP deflator at market prices ", None, "Money GDP (3), (4)"],
        [
            None,
            "Financial year",
            "2025-26 = 100",
            "per cent change on previous year",
            "Cash £ million\nNon-Season-ally Adjusted",
            "Cash £ million\nSeasonally Adjusted",
            None,
            "Calendar year",
        ],
        [None, "2024-25", N("96.757"), N("3.925132058610618"), N("2955008"), N("2945978")],
        [None, "2025-26", N("100"), N("3.3516954845644187"), N("3076302"), N("3074626")],
        [None, "2026-27 (1), (2)", "-", N("2.632760500784026"), N("3179867"), N("3187089")],
        [None, "2027-28 (1), (2)", "-", N("2.1192219342913043"), N("3291088"), N("3291022")],
        [None, "Sources and footnotes:"],
    ]
    return write_xlsx(tmp_path / "GDP_Deflators_Budget_October_2026_update.xlsx", {"28102026 deflator update": rows})


def test_gdp_deflator_layout(deflator_xlsx):
    d = rd.read_gdp_deflator(deflator_xlsx)
    assert d.base == "2025-26 = 100" and d.header_row == 6
    assert [y.year for y in d.years] == ["2024-25", "2025-26", "2026-27", "2027-28"]
    assert d.last_outturn == "2025-26" and d.first_forecast == "2026-27"
    fc = d.by_year()["2026-27"]
    assert fc.forecast and fc.index is None and fc.pct_change == Decimal("2.63276050078403")
    assert d.by_year()["2024-25"].money_gdp_nsa == Decimal(2955008)


def test_chained_index(deflator_xlsx):
    c = rd.chained_index(rd.read_gdp_deflator(deflator_xlsx))
    assert c["2025-26"] == Decimal(100)
    assert c["2026-27"] == Decimal("102.6328")
    assert c["2027-28"] == Decimal("104.8078")


def test_ons_series_blocks():
    s = rd.read_ons_series(ONS)
    assert s.meta["CDID"] == "D7BT" and s.meta["Release date"] == "21-10-2026"
    assert s.first_data_line == 9
    assert s.block_starts == {"annual": 9, "quarterly": 11, "monthly": 13}
    assert s.annual[0] == ("1988", Decimal("49.6"))
    assert s.quarterly[-1] == ("1988 Q2", Decimal("49.5"))
    assert s.latest_month == "2026 SEP" and s.monthly[-1][1] == Decimal("144.1")


def test_ons_series_rejects_unordered_months(tmp_path):
    p = tmp_path / "bad.csv"
    p.write_text('"CDID","D7BT"\n"2026 SEP","1"\n"2026 AUG","1"\n', encoding="utf-8")
    with pytest.raises(ValueError):
        rd.read_ons_series(p)
