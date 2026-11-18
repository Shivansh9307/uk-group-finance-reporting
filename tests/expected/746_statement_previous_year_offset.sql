-- Independent of the model: LAG over the financial years in order (the years of the calendar and of the plan, as in the
-- Fiscal Year table), on the statement in SQL (dw.v_statement_pnl, presentation sign).
WITH ln AS (
    SELECT line_id FROM (VALUES ('R50'), ('TOT'), ('R30'), ('R20')) AS v(line_id)
), yr AS (
    SELECT financial_year, CAST(LEFT(financial_year, 4) AS int) AS start_year
    FROM (SELECT financial_year FROM dw.dim_period GROUP BY financial_year
          UNION SELECT financial_year FROM dw.fact_plan GROUP BY financial_year) AS y
), g AS (
    SELECT l.line_id, y.financial_year, y.start_year, s.outturn AS cur
    FROM ln AS l CROSS JOIN yr AS y
    LEFT JOIN dw.v_statement_pnl AS s ON s.line_id = l.line_id AND s.financial_year = y.financial_year
), w AS (
    SELECT g.*, LAG(cur) OVER (PARTITION BY line_id ORDER BY start_year) AS py FROM g
)
SELECT line_id AS [Line Id], financial_year AS [Financial Year], CAST(cur AS decimal(38, 4)) AS statement_amount,
       CAST(py AS decimal(38, 4)) AS previous_year
FROM w
WHERE cur IS NOT NULL OR py IS NOT NULL
ORDER BY line_id, financial_year;
