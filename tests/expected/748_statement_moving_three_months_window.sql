-- Independent of the model: SUM() OVER the three allocated months (period 1 to 12) ending at each month, in the order of
-- the months across all the years of the calendar, on a grid of every period. Period 0 is not a month.
WITH ln AS (
    SELECT line_key, line_id, sign_factor FROM dw.statement_line WHERE line_id IN ('R50', 'TOT')
), grid AS (
    SELECT l.line_key, l.line_id, l.sign_factor, p.financial_year, p.period_key, p.period
    FROM ln AS l CROSS JOIN dw.dim_period AS p
), amt AS (
    SELECT m.line_key, f.period_key, SUM(f.amount_delta) AS amount
    FROM dw.fact_outturn AS f
    JOIN dw.account_statement_line AS a ON a.account_key = f.account_key
    JOIN dw.statement_line_member AS m ON m.detail_line_key = a.line_key
    WHERE m.line_key IN (SELECT line_key FROM ln)
    GROUP BY m.line_key, f.period_key
), m AS (
    SELECT g.line_id, g.financial_year, g.period_key, g.period, g.sign_factor * x.amount AS cur
    FROM grid AS g LEFT JOIN amt AS x ON x.line_key = g.line_key AND x.period_key = g.period_key
), mv AS (
    SELECT line_id, period_key,
           SUM(cur) OVER (PARTITION BY line_id ORDER BY period_key ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS moving
    FROM m WHERE period >= 1
)
SELECT m.line_id AS [Line Id], m.financial_year AS [Financial Year], m.period AS [Period Number],
       CAST(m.cur AS decimal(38, 4)) AS statement_amount, CAST(mv.moving AS decimal(38, 4)) AS moving_3_months
FROM m
LEFT JOIN mv ON mv.line_id = m.line_id AND mv.period_key = m.period_key
WHERE m.financial_year IN ('2018-19', '2019-20', '2023-24') AND (m.cur IS NOT NULL OR mv.moving IS NOT NULL)
ORDER BY m.line_id, m.financial_year, m.period;
