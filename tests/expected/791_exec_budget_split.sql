-- Independent of the model: the fact summed by the control budget of its control budget detail, 2025-26.
SELECT c.control_budget, CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS outturn
FROM dw.fact_outturn AS f
JOIN dw.dim_period AS p ON p.period_key = f.period_key
JOIN dw.dim_control_budget AS c ON c.control_budget_key = f.control_budget_key
WHERE p.financial_year = '2025-26'
GROUP BY c.control_budget
ORDER BY c.control_budget;
