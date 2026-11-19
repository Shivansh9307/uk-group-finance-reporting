"""Expected rows for tests/dax/771_real_terms_plan_by_year_source.dax: dw.fact_plan by year and plan source, and the same
amount in 2025-26 prices."""

from ukfr import model_expected

COLUMNS = ["Financial Year", "Plan Source Code", "plan", "plan_real"]

SQL = """
SELECT f.financial_year, s.plan_source_code, CAST(SUM(f.amount) AS decimal(38, 4))
FROM dw.fact_plan AS f
JOIN dw.dim_plan_source AS s ON s.plan_source_key = f.plan_source_key
WHERE f.is_part_of_other_measure = 0
GROUP BY f.financial_year, s.plan_source_code
"""


def generate(root, db):
    factor = model_expected.real_terms_factors(root)
    _, rows = db.columns(SQL)
    return COLUMNS, [[y, s, a, a * factor[y]] for y, s, a in sorted(rows)]
