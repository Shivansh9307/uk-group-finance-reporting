-- Independent of the model: window functions over a grid of every period of every year for each line, as in test 728. Current
-- is the period's own amount, YTD the running sum from period 0 within the year, PY the same period a year earlier, YoY the
-- difference. Amounts are in the line's presentation sign.
WITH ln AS (
    SELECT line_key, line_id, sign_factor FROM dw.statement_line WHERE line_id IN ('R50', 'R20', 'R30', 'TOT')
), grid AS (
    SELECT l.line_key, l.line_id, l.sign_factor, p.financial_year, p.fiscal_year_start, p.period_key, p.period
    FROM ln AS l CROSS JOIN dw.dim_period AS p
), amt AS (
    SELECT m.line_key, f.period_key, SUM(f.amount_delta) AS amount
    FROM dw.fact_outturn AS f
    JOIN dw.account_statement_line AS a ON a.account_key = f.account_key
    JOIN dw.statement_line_member AS m ON m.detail_line_key = a.line_key
    WHERE m.line_key IN (SELECT line_key FROM ln)
    GROUP BY m.line_key, f.period_key
), m AS (
    SELECT g.line_id, g.financial_year, g.fiscal_year_start, g.period, g.sign_factor * x.amount AS cur
    FROM grid AS g LEFT JOIN amt AS x ON x.line_key = g.line_key AND x.period_key = g.period_key
), w AS (
    SELECT m.*,
           SUM(cur) OVER (PARTITION BY line_id, financial_year ORDER BY period ROWS UNBOUNDED PRECEDING) AS ytd,
           LAG(cur) OVER (PARTITION BY line_id, period ORDER BY fiscal_year_start) AS py
    FROM m
), items AS (
    SELECT line_id, financial_year, period, N'Current' AS item, cur AS value FROM w
    UNION ALL SELECT line_id, financial_year, period, N'YTD', ytd FROM w
    UNION ALL SELECT line_id, financial_year, period, N'PY', py FROM w
    UNION ALL SELECT line_id, financial_year, period, N'YoY', cur - py FROM w
)
SELECT line_id AS [Line Id], financial_year AS [Financial Year], period AS [Period Number], item AS [Time Calculation],
       CAST(value AS decimal(38, 4)) AS value
FROM items
WHERE financial_year IN ('2022-23', '2023-24') AND value IS NOT NULL
ORDER BY line_id, financial_year, period, item;
