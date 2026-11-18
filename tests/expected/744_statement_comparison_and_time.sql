-- Independent of the model: dw.v_statement_pnl (the statement in SQL) turned into the five comparison items for each
-- line and year, then the previous year by LAG over the financial years in order. Actual is the outturn on the plan's
-- basis where the line has a plan, otherwise the outturn; Variance is that less the plan; Variance % is over the
-- absolute plan, in parts per million; the indicator is 1 below zero, -1 above, 0 at zero (these lines are presented as
-- reported, so the presented sign is the reported sign).
WITH ln AS (
    SELECT line_id FROM (VALUES ('R50'), ('C50'), ('TOT'), ('R30')) AS v(line_id)
), yr AS (
    SELECT financial_year, CAST(LEFT(financial_year, 4) AS int) AS start_year
    FROM (SELECT financial_year FROM dw.dim_period GROUP BY financial_year
          UNION SELECT financial_year FROM dw.fact_plan GROUP BY financial_year) AS y
), g AS (
    SELECT l.line_id, y.financial_year, y.start_year, s.outturn, s.plan_amount, s.outturn_plan_basis
    FROM ln AS l CROSS JOIN yr AS y
    LEFT JOIN dw.v_statement_pnl AS s ON s.line_id = l.line_id AND s.financial_year = y.financial_year
), c AS (
    SELECT line_id, financial_year, start_year,
           COALESCE(outturn_plan_basis, outturn) AS actual,
           plan_amount AS plan_value,
           outturn_plan_basis - plan_amount AS variance,
           (outturn_plan_basis - plan_amount) * 1000000 / NULLIF(ABS(plan_amount), 0) AS variance_ppm
    FROM g
), items AS (
    SELECT line_id, financial_year, start_year, N'Actual' AS comparison, actual AS value FROM c
    UNION ALL SELECT line_id, financial_year, start_year, N'Plan', plan_value FROM c
    UNION ALL SELECT line_id, financial_year, start_year, N'Variance', variance FROM c
    UNION ALL SELECT line_id, financial_year, start_year, N'Variance %', variance_ppm FROM c
    UNION ALL SELECT line_id, financial_year, start_year, N'Favourable/Adverse',
                    CASE WHEN variance < 0 THEN 1 WHEN variance > 0 THEN -1 WHEN variance = 0 THEN 0 END FROM c
), t AS (
    SELECT i.*, LAG(value) OVER (PARTITION BY line_id, comparison ORDER BY start_year) AS py_value FROM items AS i
), out_rows AS (
    SELECT line_id, financial_year, comparison, N'Current' AS time_calculation, value FROM t
    UNION ALL SELECT line_id, financial_year, comparison, N'YTD', value FROM t
    UNION ALL SELECT line_id, financial_year, comparison, N'PY', py_value FROM t
)
SELECT line_id AS [Line Id], financial_year AS [Financial Year], comparison AS [Comparison],
       time_calculation AS [Time Calculation], CAST(value AS decimal(38, 6)) AS value
FROM out_rows
WHERE financial_year IN ('2019-20', '2024-25') AND value IS NOT NULL
ORDER BY line_id, financial_year, comparison, time_calculation;
