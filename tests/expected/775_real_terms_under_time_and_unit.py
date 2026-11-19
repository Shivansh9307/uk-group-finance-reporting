"""Expected rows for tests/dax/775_real_terms_under_time_and_unit.dax: department 033, period 6 of 2023-24, from the
warehouse fact; each year's amount is multiplied by that year's factor, then the window is taken (Current is period 6,
YTD is periods 0 to 6, PY is period 6 of 2022-23), then the unit divides. YoY % is the real growth rate, not scaled."""

from decimal import Decimal

from ukfr import model_expected

COLUMNS = ["unit_label", "Time Calculation", "value"]
SQL = """
SELECT p.financial_year, p.period, CAST(SUM(f.amount_delta) AS decimal(38, 4))
FROM dw.fact_outturn AS f
JOIN dw.dim_period AS p ON p.period_key = f.period_key
JOIN dw.current_structure_department AS d ON d.department_key = f.current_department_key
WHERE d.department_number = '033' AND p.financial_year IN ('2022-23', '2023-24') AND p.period <= 6
GROUP BY p.financial_year, p.period
"""
UNITS = [("GBP k", Decimal(1)), ("GBP m", Decimal(1000)), ("GBP bn", Decimal(1000000))]


def generate(root, db):
    factor = model_expected.real_terms_factors(root)
    _, rows = db.columns(SQL)
    amount = {(y, p): a for y, p, a in rows}
    cur = amount[("2023-24", 6)] * factor["2023-24"]
    ytd = sum(a for (y, p), a in amount.items() if y == "2023-24") * factor["2023-24"]
    py = amount[("2022-23", 6)] * factor["2022-23"]
    items = {"Current": cur, "YTD": ytd, "PY": py, "YoY": cur - py}
    out = []
    for label, divisor in UNITS:
        for name, value in items.items():
            out.append([label, name, value / divisor])
        out.append([label, "YoY %", (cur - py) * 1000000 / abs(py)])
    return COLUMNS, out
