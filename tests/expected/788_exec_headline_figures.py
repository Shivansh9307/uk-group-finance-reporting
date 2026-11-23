"""Expected rows for tests/dax/788_exec_headline_figures.dax from the warehouse and the pinned deflator workbook."""

from decimal import Decimal

from ukfr import model_expected

COLUMNS = ["card", "value"]

OUTTURN_YEAR = """
SELECT CAST(SUM(f.amount_delta) AS decimal(38, 4)) FROM dw.fact_outturn AS f
JOIN dw.dim_period AS p ON p.period_key = f.period_key WHERE p.financial_year = '2025-26'
"""
STATEMENT_TOTAL = """
SELECT CAST(outturn_plan_basis AS decimal(38, 4)), CAST(plan_amount AS decimal(38, 4))
FROM dw.v_statement_pnl WHERE line_id = 'TOT' AND financial_year = '2025-26'
"""
OUTTURN_YTD_ALL = """
SELECT CAST(SUM(f.amount_delta) AS decimal(38, 4)) FROM dw.fact_outturn AS f
JOIN dw.dim_period AS p ON p.period_key = f.period_key WHERE p.financial_year = '2026-27' AND p.period <= 3
"""
BASIS_YTD = """
SELECT CAST(SUM(b.amount) AS decimal(38, 4)) FROM dw.outturn_plan_basis_inyear AS b
WHERE b.financial_year = '2026-27' AND b.period_no <= 3
  AND b.release_key = (SELECT MAX(r.release_key) FROM dw.dim_release AS r WHERE r.financial_year = '2026-27')
  AND b.measure IN (SELECT DISTINCT p.measure FROM dw.fact_plan AS p WHERE p.financial_year = '2026-27' AND p.is_part_of_other_measure = 0)
"""
PHASED_YTD = """
SELECT CAST(SUM(f.amount) AS decimal(38, 4)) FROM dw.fact_plan_phased AS f
WHERE f.financial_year = '2026-27' AND f.period_no <= 3 AND f.is_part_of_other_measure = 0
"""


def _one(db, sql):
    return db.columns(sql)[1][0]


def generate(root, db):
    factor = model_expected.real_terms_factors(root)
    a_out = _one(db, OUTTURN_YEAR)[0]
    a_basis, a_plan = _one(db, STATEMENT_TOTAL)
    a_var = a_basis - a_plan
    b_basis = _one(db, BASIS_YTD)[0]
    b_plan = _one(db, PHASED_YTD)[0]
    b_var = b_basis - b_plan
    b_all = _one(db, OUTTURN_YTD_ALL)[0]
    ppm = Decimal(1000000)
    rows = [
        ["a_outturn", a_out],
        ["a_outturn_plan_basis", a_basis],
        ["a_plan", a_plan],
        ["a_variance", a_var],
        ["a_variance_ppm", a_var * ppm / abs(a_plan)],
        ["a_real", a_out * factor["2025-26"]],
        ["b_outturn_plan_basis", b_basis],
        ["b_phased_plan", b_plan],
        ["b_variance", b_var],
        ["b_variance_ppm", b_var * ppm / abs(b_plan)],
        ["b_real", b_all * factor["2026-27"]],
    ]
    return COLUMNS, rows
