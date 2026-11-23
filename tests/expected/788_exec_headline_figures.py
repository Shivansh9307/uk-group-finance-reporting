"""Expected rows for tests/dax/788_exec_headline_figures.dax from the warehouse and the pinned deflator workbook.

The plan figures are for the two measures the report filter keeps (resource DEL excluding depreciation and capital DEL);
departmental AME is a forecast and is left out of the headline (see docs/reconciliation.md)."""

from decimal import Decimal

from ukfr import model_expected

COLUMNS = ["card", "value"]

OUTTURN_YEAR = """
SELECT CAST(SUM(f.amount_delta) AS decimal(38, 4)) FROM dw.fact_outturn AS f
JOIN dw.dim_period AS p ON p.period_key = f.period_key WHERE p.financial_year = '2025-26'
"""
DEL_MEASURES = "('RDEL_EX_DEPN', 'CDEL')"
PLAN_YEAR = f"""
SELECT CAST(SUM(p.amount) AS decimal(38, 4)) FROM dw.fact_plan AS p
WHERE p.financial_year = '2025-26' AND p.is_part_of_other_measure = 0 AND p.measure IN {DEL_MEASURES}
"""
BASIS_YEAR = f"""
SELECT CAST(SUM(b.amount) AS decimal(38, 4)) FROM dw.outturn_plan_basis_inyear AS b
WHERE b.financial_year = '2025-26' AND b.measure IN {DEL_MEASURES}
  AND b.release_key = (SELECT MAX(r.release_key) FROM dw.dim_release AS r WHERE r.financial_year = '2025-26')
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
  AND b.measure IN ('RDEL_EX_DEPN', 'CDEL')
"""
PHASED_YTD = """
SELECT CAST(SUM(f.amount) AS decimal(38, 4)) FROM dw.fact_plan_phased AS f
WHERE f.financial_year = '2026-27' AND f.period_no <= 3 AND f.is_part_of_other_measure = 0
  AND f.measure IN ('RDEL_EX_DEPN', 'CDEL')
"""


def _one(db, sql):
    return db.columns(sql)[1][0]


def generate(root, db):
    factor = model_expected.real_terms_factors(root)
    a_out = _one(db, OUTTURN_YEAR)[0]
    a_basis = _one(db, BASIS_YEAR)[0]
    a_plan = _one(db, PLAN_YEAR)[0]
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
