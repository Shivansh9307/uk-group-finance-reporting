-- Independent of the model: SUM() OVER the periods of each financial year in order, on a grid of every period, for the
-- lines as the statement presents them (the net lines are as reported).
WITH ln AS (
    SELECT line_key, line_id, sign_factor FROM dw.statement_line WHERE line_id IN ('R50', 'TOT')
), grid AS (
    SELECT l.line_key, l.line_id, l.sign_factor, p.financial_year, p.period_key, p.period
    FROM ln AS l CROSS JOIN dw.dim_period AS p WHERE p.financial_year IN ('2018-19', '2023-24')
), amt AS (
    SELECT m.line_key, f.period_key, SUM(f.amount_delta) AS amount
    FROM dw.fact_outturn AS f
    JOIN dw.account_statement_line AS a ON a.account_key = f.account_key
    JOIN dw.statement_line_member AS m ON m.detail_line_key = a.line_key
    WHERE m.line_key IN (SELECT line_key FROM ln)
    GROUP BY m.line_key, f.period_key
), m AS (
    SELECT g.line_id, g.financial_year, g.period, g.sign_factor * x.amount AS cur
    FROM grid AS g LEFT JOIN amt AS x ON x.line_key = g.line_key AND x.period_key = g.period_key
), w AS (
    SELECT m.*, SUM(cur) OVER (PARTITION BY line_id, financial_year ORDER BY period ROWS UNBOUNDED PRECEDING) AS running FROM m
)
SELECT line_id AS [Line Id], financial_year AS [Financial Year], period AS [Period Number],
       CAST(cur AS decimal(38, 4)) AS statement_amount, CAST(running AS decimal(38, 4)) AS running
FROM w
WHERE cur IS NOT NULL OR running IS NOT NULL
ORDER BY line_id, financial_year, period;
