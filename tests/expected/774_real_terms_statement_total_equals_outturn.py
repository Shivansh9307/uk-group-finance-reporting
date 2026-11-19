"""Expected rows for tests/dax/774_real_terms_statement_total_equals_outturn.dax."""

from ukfr import model_expected

COLUMNS = ["Financial Year", "statement_total_real", "outturn_real"]

SQL = """
SELECT p.financial_year, CAST(SUM(f.amount_delta) AS decimal(38, 4))
FROM dw.fact_outturn AS f JOIN dw.dim_period AS p ON p.period_key = f.period_key
GROUP BY p.financial_year
"""


def generate(root, db):
    factor = model_expected.real_terms_factors(root)
    _, rows = db.columns(SQL)
    return COLUMNS, [[y, a * factor[y], a * factor[y]] for y, a in sorted(rows)]
