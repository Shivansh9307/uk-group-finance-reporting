"""The forecast accuracy tests of the model cannot pass vacuously.

The with and without versions of a score differ only where a known bad return is in the cells, so a test that compares
them proves the flag works only if the two expected figures differ in the years that hold the two known cases (FCDO R0
of FY2020-21 and the Department of Health R1 of FY2018-19). These checks read the committed expected values and the
committed test results, and need no database and no Desktop.
"""

from __future__ import annotations

import csv
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXPECTED = ROOT / "tests" / "expected"
RESULTS = ROOT / "tests" / "results"
YEARS_WITH_A_KNOWN_CASE = {"2018-19", "2020-21"}


def _rows(path: Path) -> list[dict]:
    with path.open(encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def test_the_with_and_without_figures_differ_in_the_two_years_that_hold_a_known_bad_return():
    name = "922_forecast_department_by_year_with_and_without_the_known_bad_returns.csv"
    rows = {r["financial_year"]: r for r in _rows(EXPECTED / name)}
    assert YEARS_WITH_A_KNOWN_CASE <= set(rows)
    for year in YEARS_WITH_A_KNOWN_CASE:
        r = rows[year]
        assert Decimal(r["abs_error"]) != Decimal(r["abs_error_excl"]), year
        assert Decimal(r["wape"]) != Decimal(r["wape_excl"]), year
        assert int(r["bad_cells"]) > 0, year


def test_the_two_known_cells_are_flagged_have_an_error_and_no_cell_without_the_bad_returns():
    rows = _rows(EXPECTED / "923_forecast_the_two_known_bad_return_cells.csv")
    assert {(r["department_group_code"], r["financial_year"], r["return_label"]) for r in rows} == {
        ("DID030.GROUP", "2020-21", "R0"),
        ("DOH033.GROUP", "2018-19", "R1"),
    }
    for r in rows:
        assert int(r["bad_cells"]) >= 1 and int(r["cells_excl"]) == 0
        assert Decimal(r["abs_error"]) > 0


def test_the_pay_line_has_four_methods_and_the_total_line_three_in_the_committed_expected_values():
    pay = {r["method"] for r in _rows(EXPECTED / "925_forecast_pay_line_four_methods_by_year_common_cells.csv")}
    total = {r["method"] for r in _rows(EXPECTED / "921_forecast_total_line_by_method_and_year_common_cells.csv")}
    assert pay == {"Department", "Run rate", "Seasonal", "FTE x cost"}
    assert total == {"Department", "Run rate", "Seasonal"}
