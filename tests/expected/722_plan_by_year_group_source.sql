-- Independent of the model: the plan fact on its own keys, without the rows that are part of another measure.
SELECT f.financial_year AS [Financial Year], g.sr_group_name AS [Spending Review Group],
       s.plan_source_code AS [Plan Source Code], CAST(SUM(f.amount) AS decimal(38, 4)) AS [plan]
FROM dw.fact_plan AS f
JOIN dw.dim_sr_group AS g ON g.sr_group_key = f.sr_group_key
JOIN dw.dim_plan_source AS s ON s.plan_source_key = f.plan_source_key
WHERE f.is_part_of_other_measure = 0
GROUP BY f.financial_year, g.sr_group_name, s.plan_source_code
ORDER BY f.financial_year, g.sr_group_name, s.plan_source_code;
