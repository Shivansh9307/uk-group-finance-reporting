"""Expected rows for tests/dax/772_real_terms_outturn_by_year_department.dax."""

from ukfr import model_expected

COLUMNS = ["Financial Year", "Department Number", "outturn", "outturn_real"]

SQL = """
SELECT p.financial_year, d.department_number, CAST(SUM(f.amount_delta) AS decimal(38, 4))
FROM dw.fact_outturn AS f
JOIN dw.dim_period AS p ON p.period_key = f.period_key
JOIN dw.current_structure_department AS d ON d.department_key = f.current_department_key
GROUP BY p.financial_year, d.department_number
"""


def generate(root, db):
    factor = model_expected.real_terms_factors(root)
    _, rows = db.columns(SQL)
    return COLUMNS, [[y, d, a, a * factor[y]] for y, d, a in sorted(rows)]
