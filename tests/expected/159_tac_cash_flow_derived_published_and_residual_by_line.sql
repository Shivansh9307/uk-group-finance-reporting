-- requires: dw.tac_fact
-- Independent of the model views: the derived amounts of dw.tac_cash_flow_derived by year and line, and the published
-- lines of dw.tac_fact (current-year column, lines of kind line) compared with each line through
-- dw.tac_cash_flow_comparison; the residual is derived less published, a missing side counting as 0.
WITH derived AS (
    SELECT d.release, d.cash_flow_line_key, SUM(d.amount) AS amount
    FROM dw.tac_cash_flow_derived AS d GROUP BY d.release, d.cash_flow_line_key
),
published AS (
    SELECT f.release, c.cash_flow_line_key, SUM(f.value) AS amount
    FROM dw.tac_fact AS f
    JOIN dw.tac_cash_flow_comparison AS c ON c.line_key = f.line_key
    WHERE f.period_column = 'CY'
    GROUP BY f.release, c.cash_flow_line_key
)
SELECT d.release AS [Financial Year], l.line_code AS [Line Code],
       CAST(d.amount AS decimal(38, 4)) AS derived,
       CAST(p.amount AS decimal(38, 4)) AS published,
       CAST(ISNULL(d.amount, 0) - ISNULL(p.amount, 0) AS decimal(38, 4)) AS residual
FROM derived AS d
JOIN dw.tac_cash_flow_line AS l ON l.cash_flow_line_key = d.cash_flow_line_key
LEFT JOIN published AS p ON p.release = d.release AND p.cash_flow_line_key = d.cash_flow_line_key
ORDER BY d.release, l.line_code;
