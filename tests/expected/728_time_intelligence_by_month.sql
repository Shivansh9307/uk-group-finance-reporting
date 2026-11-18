-- Independent of the model: window functions over a grid of every period of every year for each department (see
-- test 727). Here the calculation is read at each period: the month is the period's own amount (periods 1 to 12), the
-- quarter to date runs from the first month of the fiscal quarter, the year to date from period 0, the previous year is
-- the same period one year earlier, and the rolling window is the twelve allocated months ending at the period.
WITH dept AS (SELECT department_number FROM (VALUES ('022'), ('003')) AS v(department_number)),
grid AS (
    SELECT p.financial_year, p.fiscal_year_start, p.period_key, p.period, p.fiscal_quarter, d.department_number
    FROM dw.dim_period AS p CROSS JOIN dept AS d
), m AS (
    SELECT g.financial_year, g.fiscal_year_start, g.period, g.fiscal_quarter, g.department_number,
           SUM(f.amount_delta) AS amt
    FROM grid AS g
    LEFT JOIN (SELECT o.period_key, c.department_number, o.amount_delta
               FROM dw.fact_outturn AS o JOIN dw.current_structure_department AS c ON c.department_key = o.current_department_key) AS f
           ON f.period_key = g.period_key AND f.department_number = g.department_number
    GROUP BY g.financial_year, g.fiscal_year_start, g.period, g.fiscal_quarter, g.department_number
), w AS (
    SELECT m.*,
           SUM(amt) OVER (PARTITION BY department_number, financial_year ORDER BY period ROWS UNBOUNDED PRECEDING) AS ytd,
           SUM(amt) OVER (PARTITION BY department_number, financial_year, fiscal_quarter ORDER BY period ROWS UNBOUNDED PRECEDING) AS qtd,
           LAG(amt) OVER (PARTITION BY department_number, period ORDER BY fiscal_year_start) AS py
    FROM m
), months AS (
    SELECT department_number, financial_year, period, fiscal_year_start * 12 + period - 1 AS month_index, amt
    FROM m WHERE period >= 1
), r AS (
    SELECT department_number, financial_year, period,
           SUM(amt) OVER (PARTITION BY department_number ORDER BY month_index ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS r12
    FROM months
), z AS (
    SELECT w.department_number, w.financial_year, w.period, w.amt AS cur, w.ytd, w.qtd, w.py, r.r12
    FROM w LEFT JOIN r ON r.department_number = w.department_number AND r.financial_year = w.financial_year AND r.period = w.period
), items AS (
    SELECT department_number, financial_year, period, N'Current' AS item, cur AS value FROM z
    UNION ALL SELECT department_number, financial_year, period, N'MTD', CASE WHEN period >= 1 THEN cur END FROM z
    UNION ALL SELECT department_number, financial_year, period, N'QTD', CASE WHEN period >= 1 THEN qtd END FROM z
    UNION ALL SELECT department_number, financial_year, period, N'YTD', ytd FROM z
    UNION ALL SELECT department_number, financial_year, period, N'PY', py FROM z
    UNION ALL SELECT department_number, financial_year, period, N'YoY', cur - py FROM z
    UNION ALL SELECT department_number, financial_year, period, N'YoY %', (cur - py) * 1000000 / NULLIF(ABS(py), 0) FROM z
    UNION ALL SELECT department_number, financial_year, period, N'Rolling 12 months', r12 FROM z
)
SELECT financial_year AS [Financial Year], period AS [Period Number], department_number AS [Department Number],
       item AS [Time Calculation], CAST(value AS decimal(38, 6)) AS value
FROM items
WHERE financial_year IN ('2018-19', '2019-20', '2024-25') AND value IS NOT NULL
ORDER BY financial_year, period, department_number, item;
