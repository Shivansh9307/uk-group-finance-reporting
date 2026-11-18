-- Independent of the model: the plan fact and the phased fact, each summed by year and group on its own table.
WITH p AS (
    SELECT financial_year, sr_group_key, SUM(amount) AS [plan]
    FROM dw.fact_plan WHERE is_part_of_other_measure = 0 GROUP BY financial_year, sr_group_key
), ph AS (
    SELECT d.financial_year, f.sr_group_key, SUM(f.amount) AS phased
    FROM dw.fact_plan_phased AS f JOIN dw.dim_period AS d ON d.period_key = f.period_key
    WHERE f.is_part_of_other_measure = 0 GROUP BY d.financial_year, f.sr_group_key
)
SELECT p.financial_year AS [Financial Year], g.sr_group_name AS [Spending Review Group],
       CAST(p.[plan] AS decimal(38, 4)) AS [plan], CAST(ph.phased AS decimal(38, 4)) AS phased
FROM p
JOIN dw.dim_sr_group AS g ON g.sr_group_key = p.sr_group_key
LEFT JOIN ph ON ph.financial_year = p.financial_year AND ph.sr_group_key = p.sr_group_key
ORDER BY p.financial_year, g.sr_group_name;
