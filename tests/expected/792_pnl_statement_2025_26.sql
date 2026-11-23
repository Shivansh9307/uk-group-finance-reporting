-- Independent of the model: dw.v_statement_pnl for 2025-26, the variance as the outturn on the plan's basis less the plan
-- (only where both exist), its share of the absolute plan in parts per million, and the same line's amount in 2024-25.
SELECT c.line_id, CAST(c.outturn AS decimal(38, 4)) AS amount, CAST(c.plan_amount AS decimal(38, 4)) AS [plan],
       CAST(CASE WHEN c.plan_amount IS NOT NULL AND c.outturn_plan_basis IS NOT NULL THEN c.outturn_plan_basis - c.plan_amount END AS decimal(38, 4)) AS variance,
       CAST(CASE WHEN c.plan_amount IS NOT NULL AND c.outturn_plan_basis IS NOT NULL AND c.plan_amount <> 0
                 THEN (c.outturn_plan_basis - c.plan_amount) * 1000000 / ABS(c.plan_amount) END AS decimal(38, 4)) AS variance_ppm,
       CAST(pv.outturn AS decimal(38, 4)) AS previous
FROM dw.v_statement_pnl AS c
LEFT JOIN dw.v_statement_pnl AS pv ON pv.line_id = c.line_id AND pv.financial_year = '2024-25'
WHERE c.financial_year = '2025-26'
ORDER BY c.line_id;
