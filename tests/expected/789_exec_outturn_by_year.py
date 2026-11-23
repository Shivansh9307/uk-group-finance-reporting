"""Expected rows for tests/dax/789_exec_outturn_by_year.dax."""

from ukfr import model_expected

COLUMNS = ["financial_year", "outturn", "outturn_real"]

SQL = """
SELECT p.financial_year, CAST(SUM(f.amount_delta) AS decimal(38, 4))
FROM dw.fact_outturn AS f JOIN dw.dim_period AS p ON p.period_key = f.period_key
WHERE p.financial_year <= '2025-26'
GROUP BY p.financial_year
"""


def generate(root, db):
    factor = model_expected.real_terms_factors(root)
    _, rows = db.columns(SQL)
    return COLUMNS, [[y, a, a * factor[y]] for y, a in sorted(rows)]
