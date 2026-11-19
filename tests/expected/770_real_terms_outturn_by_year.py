"""Expected rows for tests/dax/770_real_terms_outturn_by_year.dax: the outturn of each financial year from the warehouse
fact, the chained index of the default vintage from the pinned workbook, and the outturn times 100 / index."""

from ukfr import model_expected

COLUMNS = ["Financial Year", "outturn", "index", "outturn_real"]

YEARS_SQL = """
SELECT financial_year FROM dw.dim_period
UNION
SELECT financial_year FROM dw.fact_plan
"""
OUTTURN_SQL = """
SELECT p.financial_year, CAST(SUM(f.amount_delta) AS decimal(38, 4))
FROM dw.fact_outturn AS f JOIN dw.dim_period AS p ON p.period_key = f.period_key
GROUP BY p.financial_year
"""


def generate(root, db):
    index = model_expected.real_terms_index(root)
    factor = model_expected.real_terms_factors(root)
    _, years = db.columns(YEARS_SQL)
    _, amounts = db.columns(OUTTURN_SQL)
    outturn = {y: a for y, a in amounts}
    rows = []
    for (year,) in sorted(years):
        amount = outturn.get(year)
        real = None if amount is None else amount * factor[year]
        rows.append([year, amount, index[year], real])
    return COLUMNS, rows
