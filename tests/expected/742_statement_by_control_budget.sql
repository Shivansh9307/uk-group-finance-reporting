-- Independent of the model: the outturn fact joined to its period, control budget and the account's statement line, summed
-- to every line that adds the detail line up, in the line's presentation sign.
SELECT l.line_id AS [Line Id], p.financial_year AS [Financial Year], cb.control_budget AS [Control Budget],
       CAST(SUM(f.amount_delta) * MAX(l.sign_factor) AS decimal(38, 4)) AS value
FROM dw.fact_outturn AS f
JOIN dw.dim_period AS p ON p.period_key = f.period_key
JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = f.control_budget_key
JOIN dw.account_statement_line AS a ON a.account_key = f.account_key
JOIN dw.statement_line_member AS m ON m.detail_line_key = a.line_key
JOIN dw.statement_line AS l ON l.line_key = m.line_key
WHERE l.line_id IN ('R20', 'R30', 'R50', 'C50', 'N30', 'TOT') AND p.financial_year IN ('2019-20', '2024-25')
GROUP BY l.line_id, p.financial_year, cb.control_budget
ORDER BY l.line_id, p.financial_year, cb.control_budget;
