-- Independent of the model: the five comparison items of three statement cells from dw.v_statement_pnl, divided by 1, 1,000
-- and 1,000,000 for the unit (the percentage in parts per million and the indicator are not scaled).
WITH cells AS (
    SELECT s.line_id, s.financial_year, COALESCE(s.outturn_plan_basis, s.outturn) AS actual, s.plan_amount AS plan_value,
           s.outturn_plan_basis - s.plan_amount AS variance
    FROM dw.v_statement_pnl AS s
    WHERE (s.line_id = 'R50' AND s.financial_year = '2019-20') OR (s.line_id = 'TOT' AND s.financial_year = '2024-25')
       OR (s.line_id = 'R20' AND s.financial_year = '2024-25')
), units AS (
    SELECT u.label, u.divisor FROM (VALUES (N'GBP k', CAST(1 AS decimal(19, 4))), (N'GBP m', CAST(1000 AS decimal(19, 4))), (N'GBP bn', CAST(1000000 AS decimal(19, 4)))) AS u(label, divisor)
), items AS (
    SELECT c.line_id, c.financial_year, units.label AS unit_label, N'Actual' AS comparison, c.actual / units.divisor AS value FROM cells AS c CROSS JOIN units
    UNION ALL SELECT c.line_id, c.financial_year, units.label, N'Plan', c.plan_value / units.divisor FROM cells AS c CROSS JOIN units
    UNION ALL SELECT c.line_id, c.financial_year, units.label, N'Variance', c.variance / units.divisor FROM cells AS c CROSS JOIN units
    UNION ALL SELECT c.line_id, c.financial_year, units.label, N'Variance %', c.variance * 1000000 / NULLIF(ABS(c.plan_value), 0) FROM cells AS c CROSS JOIN units
    UNION ALL SELECT c.line_id, c.financial_year, units.label, N'Favourable/Adverse',
                     CASE WHEN c.variance < 0 THEN 1 WHEN c.variance > 0 THEN -1 WHEN c.variance = 0 THEN 0 END FROM cells AS c CROSS JOIN units
)
SELECT line_id AS [Line Id], financial_year AS [Financial Year], unit_label, comparison AS [Comparison],
       CAST(value AS decimal(38, 6)) AS value
FROM items
WHERE value IS NOT NULL
ORDER BY line_id, financial_year, unit_label, comparison;
