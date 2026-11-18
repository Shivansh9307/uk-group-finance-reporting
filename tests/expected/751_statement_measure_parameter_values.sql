-- Independent of the model: the four values of the field parameter (outturn, plan, variance, variance % in parts per
-- million) of two statement cells, from dw.v_statement_pnl. Variance is the outturn on the plan's basis less the plan.
WITH cells AS (
    SELECT s.line_id, s.financial_year, s.outturn, s.plan_amount, s.outturn_plan_basis - s.plan_amount AS variance
    FROM dw.v_statement_pnl AS s
    WHERE (s.line_id = 'R50' AND s.financial_year = '2019-20') OR (s.line_id = 'TOT' AND s.financial_year = '2024-25')
)
SELECT p.name AS [Statement Measure], c.line_id AS [Line Id], c.financial_year AS [Financial Year],
       CAST(CASE p.name WHEN N'Outturn' THEN c.outturn
                        WHEN N'Plan' THEN c.plan_amount
                        WHEN N'Variance' THEN c.variance
                        WHEN N'Variance %' THEN c.variance * 1000000 / NULLIF(ABS(c.plan_amount), 0) END AS decimal(38, 6)) AS value
FROM cells AS c
CROSS JOIN (VALUES (N'Outturn'), (N'Plan'), (N'Variance'), (N'Variance %')) AS p(name)
ORDER BY p.name, c.line_id;
