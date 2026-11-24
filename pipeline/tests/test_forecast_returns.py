"""The forecast-return load stage and its independent control, on small zips written for the test.

The stage adds each member's rows up into cells; the control recomputes row counts and sums month by month
without the readers. On the same fixtures they must agree, which is what the real run checks on the real files.
"""

from __future__ import annotations

import zipfile
from decimal import Decimal
from pathlib import Path

import pytest

from ukfr.controls import forecast_independent as ctl
from ukfr.readers import oscar_extract as rx
from ukfr.stages import forecast_returns as fr

EXTRA = ("ORGANISATION_LONG_NAME", "SEGMENT_L4_CODE", "SR_GROUP_CODE", "CONTROL_BUDGET_L0_LONG_NAME")


def _header(n_columns: int | None = None) -> list[str]:
    cols = list(dict.fromkeys([*rx.REQUIRED, *EXTRA]))
    if n_columns:
        cols += [f"FILLER_{i}" for i in range(n_columns - len(cols))]
    return cols


def _row(header: list[str], **values: str) -> list[str]:
    base = dict.fromkeys(header, "")
    base.update(
        {
            "DEPARTMENT_GROUP_CODE": "DFT004.GROUP",
            "DEPARTMENT_GROUP_LONG_NAME": "DEPARTMENT FOR TRANSPORT (GROUP)",
            "SR_GROUP_CODE": "SR_004",
            "ORGANISATION_CODE": "DFT004",
            "ORGANISATION_LONG_NAME": "Department for Transport",
            "ECONOMIC_CATEGORY_CODE": "A101",
            "STATUS_CODE": "CONFIRMED",
            "TYPE_CODE": "TYPE_INYEAR",
        }
    )
    base.update(values)
    return [base[c] for c in header]


def _extract_zip(tmp_path: Path) -> Path:
    h = _header(rx.N_COLUMNS)
    common = {
        "CONTROL_BUDGET_L0_LONG_NAME": "DEPARTMENTAL EXPENDITURE LIMITS",
        "CONTROL_BUDGET_L1_LONG_NAME": "DEPARTMENTAL EXPENDITURE LIMITS PROGRAMME",
        "ECONOMIC_BUDGET_CODE": "RESOURCE",
        "YEAR_SHORT_NAME": "2018-19",
    }
    rows = [
        # R1: two source rows of one cell (one of them with a different sub-segment), then a DRAFT row
        _row(
            h, VERSION_CODE="R1", MONTH_SHORT_NAME="Apr-18", AMOUNT=" 000000000005000.", SEGMENT_L4_CODE="X1", **common
        ),
        _row(
            h, VERSION_CODE="R1", MONTH_SHORT_NAME="Apr-18", AMOUNT="-000000000000336.", SEGMENT_L4_CODE="X2", **common
        ),
        _row(h, VERSION_CODE="R1", MONTH_SHORT_NAME="May-18", AMOUNT=" 000000000000100.", **common),
        _row(
            h, VERSION_CODE="R1", MONTH_SHORT_NAME="Apr-18", AMOUNT=" 000000000000007.", STATUS_CODE="DRAFT", **common
        ),
        # R13 with a period 0 row, and a plan row that must not be counted
        _row(h, VERSION_CODE="R13", MONTH_SHORT_NAME="Period 0 - 18-19", AMOUNT=" 000000000000011.", **common),
        _row(h, VERSION_CODE="R13", MONTH_SHORT_NAME="Mar-19", AMOUNT=" 000000000000002.", **common),
        _row(h, VERSION_CODE="PLANS", MONTH_SHORT_NAME="Period 0 - 18-19", AMOUNT=" 000000000099999.", **common),
    ]
    text = "\r\n".join("|".join(f'"{v}"' for v in r) for r in [h, *rows]) + "\r\n"
    p = tmp_path / "2022_OSCAR_Extract_2018_19.zip"
    with zipfile.ZipFile(p, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr("extract_2018_19.txt", text.encode("cp1252"))
    return p


def _mfo_zip(tmp_path: Path) -> Path:
    h = _header()
    common = {
        "CONTROL_BUDGET_L0_LONG_NAME": "DEPT AME",
        "CONTROL_BUDGET_L1_LONG_NAME": "AME",
        "ECONOMIC_BUDGET_CODE": "CAPITAL",
        "YEAR_SHORT_NAME": "202223",
        "STATUS_CODE": "Locked",
    }
    rows = [
        _row(h, MONTH_SHORT_NAME="P01", AMOUNT="1.5", **common),
        _row(h, MONTH_SHORT_NAME="P01", AMOUNT="2.0000000005", **common),
        _row(h, MONTH_SHORT_NAME="P02", AMOUNT="-3", **common),
    ]
    text = "\r\n".join(",".join(f'"{v}"' for v in r) for r in [h, *rows]) + "\r\n"
    p = tmp_path / "MFO_2022-23_New.zip"
    with zipfile.ZipFile(p, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr("MFO-R03-2022-23.csv", text.encode("cp1252"))
    return p


def test_extract_cells_add_rows_exactly(tmp_path):
    p = _extract_zip(tmp_path)
    by_return, rows_per_return, read = fr.extract_cells(p, rx.member_name(p))
    assert read == 7 and rows_per_return == {1: 4, 13: 2}  # the plan row is read, not counted
    r1 = by_return[1]
    cell = r1[
        (
            1,
            "CONFIRMED",
            "TYPE_INYEAR",
            "DFT004.GROUP",
            "SR_004",
            "DFT004",
            "A101",
            "DEPARTMENTAL EXPENDITURE LIMITS",
            "DEPARTMENTAL EXPENDITURE LIMITS PROGRAMME",
            "RESOURCE",
        )
    ]
    assert (cell.amount, cell.rows, cell.first_line, cell.last_line) == (Decimal("4664"), 2, 1, 2)
    assert len(r1) == 3  # April confirmed, May confirmed, April draft: status keeps cells apart
    assert {k[0] for k in by_return[13]} == {0, 12}  # period 0 is kept


def test_mfo_cells_keep_exact_decimals(tmp_path):
    p = _mfo_zip(tmp_path)
    cells, read, repaired = fr.mfo_cells(p, "MFO-R03-2022-23.csv")
    assert (read, repaired) == (3, 0)
    amounts = {k[0]: c.amount for k, c in cells.items()}
    assert amounts == {1: Decimal("3.5000000005"), 2: Decimal("-3")}


def test_stage_and_independent_control_agree_on_the_same_files(tmp_path):
    ex, mf = _extract_zip(tmp_path), _mfo_zip(tmp_path)
    by_return, _rows, _read = fr.extract_cells(ex, rx.member_name(ex))
    stage: dict[tuple, tuple[int, Decimal]] = {}
    for ret, cells in by_return.items():
        for key, c in cells.items():
            n, a = stage.get(("extract", "2018-19", ret, key[0]), (0, Decimal(0)))
            stage[("extract", "2018-19", ret, key[0])] = (n + c.rows, a + c.amount)
    cells, _read, _repaired = fr.mfo_cells(mf, "MFO-R03-2022-23.csv")
    for key, c in cells.items():
        n, a = stage.get(("mfo", "2022-23", 3, key[0]), (0, Decimal(0)))
        stage[("mfo", "2022-23", 3, key[0])] = (n + c.rows, a + c.amount)
    independent = {**ctl._extract(ex, "extract"), **ctl._mfo(mf, "mfo")}
    assert {k: (v[0], v[1]) for k, v in independent.items()} == stage


def test_a_sixteen_decimal_amount_is_accepted_and_a_seventeen_decimal_one_is_not():
    fr.check_scale(Decimal("1.00E-16"), "x")
    with pytest.raises(ValueError, match="decimal places"):
        fr.check_scale(Decimal("1.0000000000000001E-1"), "x")


def test_period_text_in_the_control_matches_the_reader():
    for text in ("Period 0 - 17-18", "Apr-17", "Mar-18", "P01", "P12"):
        expected = rx.month_period(text) if text[0] != "P" or text.startswith("Period") else int(text[1:])
        assert ctl._period(text) == expected
    with pytest.raises(SystemExit):
        ctl._period("Smarch-18")


def test_cell_tuples_are_sorted_and_numbered_from_the_given_id():
    cells: dict[tuple, fr.Cell] = {}
    base = ("CONFIRMED", "TYPE_INYEAR", "G", "S", "O", "A101", "l0", "l1", "RESOURCE")
    fr.add_row(cells, (2, *base), Decimal("1"), 5, "g", "o")
    fr.add_row(cells, (1, *base), Decimal("2"), 6, "g", "o")
    fr.add_row(cells, (1, *base), Decimal("3"), 9, "g", "o")
    rows = list(fr.cell_tuples(7, 4, cells, 100))
    assert [r[1] for r in rows] == [100, 101]
    assert [r[3] for r in rows] == [1, 2]  # period order
    assert rows[0][15:] == (Decimal("5"), 2, 6, 9)  # amount, rows, first and last line


@pytest.mark.db
@pytest.mark.localdata
def test_own_forecast_arithmetic_agrees_with_python_decimals(db):
    """Both methods recomputed in Python from the loaded rows of return n (months up to n) and the prior year's R13."""
    if db.scalar("SELECT OBJECT_ID(N'dw.forecast_own')") is None:
        pytest.skip("dw.forecast_own is not in this database (built without the full scope)")
    from decimal import ROUND_HALF_UP, localcontext

    cells = db.query(
        "SELECT TOP (40) financial_year, return_no, department_group_code, budget_measure "
        "FROM dw.forecast_own WHERE method = 'seasonal' AND return_no IN (3, 6, 9) "
        "GROUP BY financial_year, return_no, department_group_code, budget_measure "
        "ORDER BY CHECKSUM(financial_year, return_no, department_group_code, budget_measure)"
    )
    assert cells
    for fy, n, dgc, bm in cells:
        known = {
            p: a
            for p, a in db.query(
                "SELECT period, SUM(amount) FROM dw.forecast_return WHERE financial_year = ? AND return_no = ? "
                "AND department_group_code = ? AND budget_measure = ? AND period BETWEEN 1 AND ? GROUP BY period",
                (fy, n, dgc, bm, n),
            )
        }
        prior = {
            p: a
            for p, a in db.query(
                "SELECT r.period, SUM(r.amount) FROM dw.forecast_return AS r "
                "JOIN dw.forecast_prior_profile AS pp ON pp.profile_financial_year = r.financial_year "
                "AND pp.financial_year = ? AND pp.department_group_code = r.department_group_code "
                "AND pp.budget_measure = r.budget_measure AND pp.period = r.period "
                "WHERE r.return_no = 13 AND r.department_group_code = ? AND r.budget_measure = ? GROUP BY r.period",
                (fy, dgc, bm),
            )
        }
        ytd = sum(known.values(), Decimal(0))
        prior_ytd = sum((a for p, a in prior.items() if p <= n), Decimal(0))
        for method, period, amount in db.query(
            "SELECT method, period, amount FROM dw.forecast_own WHERE financial_year = ? AND return_no = ? "
            "AND department_group_code = ? AND budget_measure = ?",
            (fy, n, dgc, bm),
        ):
            with localcontext() as ctx:
                ctx.prec = 60
                want = ytd / n if method == "run_rate" else ytd * prior.get(period, Decimal(0)) / prior_ytd
                want = want.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)
            assert abs(Decimal(amount) - want) <= Decimal("0.0001"), (fy, n, dgc, bm, method, period)
