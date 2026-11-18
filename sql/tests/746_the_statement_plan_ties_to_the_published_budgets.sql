-- test: the plan on the total line of the statement for 2024-25 is the sum of the four published budgets (resource DEL excluding depreciation 487,520,000, capital DEL 114,587,000, departmental AME resource 551,762,000 and capital 102,672,000, GBP thousands: the totals that sql/tests/509 ties dw.fact_plan to), and administration rows are not added on top
SELECT 'total plan of 2024-25 is not the sum of the four published budgets' AS problem, CAST(plan_amount AS nvarchar(40)) AS detail
FROM dw.v_statement_pnl
WHERE line_id = 'TOT' AND financial_year = '2024-25'
  AND plan_amount <> 487520000 + 114587000 + 551762000 + 102672000
UNION ALL
SELECT 'no plan on the total line of 2024-25', ''
WHERE NOT EXISTS (SELECT 1 FROM dw.v_statement_pnl WHERE line_id = 'TOT' AND financial_year = '2024-25' AND plan_amount IS NOT NULL);
