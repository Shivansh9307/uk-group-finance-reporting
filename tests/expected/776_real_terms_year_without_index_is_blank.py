"""Expected rows for tests/dax/776_real_terms_year_without_index_is_blank.dax: the nominal outturn of each scope from the
warehouse fact; the real-terms value where every year has an index (2023-24, and 2025-26 which is the base), and BLANK where
the year without an index (2024-25) is in the scope."""

from ukfr import model_expected

COLUMNS = ["scope", "outturn", "outturn_real"]
SQL = """
SELECT p.financial_year, CAST(SUM(f.amount_delta) AS decimal(38, 4))
FROM dw.fact_outturn AS f JOIN dw.dim_period AS p ON p.period_key = f.period_key
WHERE p.financial_year IN ('2023-24', '2024-25', '2025-26')
GROUP BY p.financial_year
"""


def generate(root, db):
    factor = model_expected.real_terms_factors(root)
    _, rows = db.columns(SQL)
    a = dict(rows)
    return COLUMNS, [
        ["2023-24", a["2023-24"], a["2023-24"] * factor["2023-24"]],
        ["2024-25", a["2024-25"], None],
        ["2025-26", a["2025-26"], a["2025-26"] * factor["2025-26"]],
        ["2023-24 to 2025-26", sum(a.values()), None],
    ]
