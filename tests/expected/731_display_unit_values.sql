-- Independent of the model: actual and plan of the cell from the warehouse tables, then the five comparison items
-- divided by 1, 1,000 and 1,000,000 for the unit (the percentage in parts per million and the indicator are not scaled).
WITH pl AS (
    SELECT SUM(p.amount) AS plan_amt
    FROM dw.fact_plan AS p
    WHERE p.grain_code = 'A' AND p.measure = 'RDEL' AND p.organisation_code = 'DFE022' AND p.financial_year = '2019-20'
), ac AS (
    SELECT SUM(f.amount_delta) AS act_amt
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS d ON d.period_key = f.period_key
    JOIN dw.dim_organisation AS o ON o.organisation_key = f.organisation_key
    JOIN dw.dim_account AS a ON a.account_key = f.account_key
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = f.control_budget_key
    WHERE o.organisation_code = 'DFE022' AND cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN')
      AND a.economic_budget = 'RESOURCE' AND d.financial_year = '2019-20'
), units AS (
    SELECT u.label, u.divisor FROM (VALUES (N'GBP k', CAST(1 AS decimal(19, 4))), (N'GBP m', CAST(1000 AS decimal(19, 4))), (N'GBP bn', CAST(1000000 AS decimal(19, 4)))) AS u(label, divisor)
), items AS (
    SELECT units.label AS unit_label, N'Actual' AS comparison, ac.act_amt / units.divisor AS value FROM ac CROSS JOIN units
    UNION ALL SELECT units.label, N'Plan', pl.plan_amt / units.divisor FROM pl CROSS JOIN units
    UNION ALL SELECT units.label, N'Variance', (ac.act_amt - pl.plan_amt) / units.divisor FROM ac CROSS JOIN pl CROSS JOIN units
    UNION ALL SELECT units.label, N'Variance %', (ac.act_amt - pl.plan_amt) * 1000000 / NULLIF(ABS(pl.plan_amt), 0) FROM ac CROSS JOIN pl CROSS JOIN units
    UNION ALL SELECT units.label, N'Favourable/Adverse', CASE WHEN ac.act_amt - pl.plan_amt < 0 THEN 1 WHEN ac.act_amt - pl.plan_amt > 0 THEN -1 ELSE 0 END FROM ac CROSS JOIN pl CROSS JOIN units
)
SELECT unit_label, comparison AS [Comparison], CAST(value AS decimal(38, 6)) AS value
FROM items
ORDER BY unit_label, comparison;
