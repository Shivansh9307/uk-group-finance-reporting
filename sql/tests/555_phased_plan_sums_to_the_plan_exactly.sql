-- test: every dw.fact_plan row that has a calendar is spread over periods 1 to 12 exactly once, the twelve amounts add up to the plan amount with no difference at all, every phased row is derived and the Plan (phased) scenario, and the plan fact itself carries no phased amount
SELECT 'plan row with a calendar not phased over twelve periods' AS problem, CAST(p.plan_fact_key AS nvarchar(20)) AS detail
FROM dw.fact_plan AS p
LEFT JOIN dw.fact_plan_phased AS x ON x.plan_fact_key = p.plan_fact_key
WHERE EXISTS (SELECT 1 FROM dw.dim_period AS d WHERE d.financial_year = p.financial_year)
GROUP BY p.plan_fact_key
HAVING COUNT(x.plan_fact_key) <> 12 OR COUNT(DISTINCT x.period_no) <> 12
UNION ALL
SELECT 'phased amounts differ from the plan amount', CAST(p.plan_fact_key AS nvarchar(20))
FROM dw.fact_plan AS p
JOIN dw.fact_plan_phased AS x ON x.plan_fact_key = p.plan_fact_key
GROUP BY p.plan_fact_key, p.amount
HAVING SUM(x.amount) <> p.amount
UNION ALL
SELECT 'phased row for a plan row that does not exist', CAST(x.plan_fact_key AS nvarchar(20))
FROM dw.fact_plan_phased AS x
WHERE NOT EXISTS (SELECT 1 FROM dw.fact_plan AS p WHERE p.plan_fact_key = x.plan_fact_key)
UNION ALL
SELECT 'phased row without the phased scenario or the derived flag', CAST(x.plan_fact_key AS nvarchar(20))
FROM dw.fact_plan_phased AS x
WHERE x.is_derived <> 1 OR x.scenario_key <> (SELECT scenario_key FROM dw.dim_scenario WHERE scenario_name = N'Plan (phased)')
UNION ALL
SELECT 'phased row keeps a different key or flag than its plan row', CAST(x.plan_fact_key AS nvarchar(20))
FROM dw.fact_plan_phased AS x
JOIN dw.fact_plan AS p ON p.plan_fact_key = x.plan_fact_key
WHERE x.measure <> p.measure OR x.sr_group_key <> p.sr_group_key OR x.financial_year <> p.financial_year
   OR x.is_part_of_other_measure <> p.is_part_of_other_measure OR x.grain_code <> p.grain_code
   OR x.plan_source_key <> p.plan_source_key OR ISNULL(x.organisation_code, N'') <> ISNULL(p.organisation_code, N'')
UNION ALL
SELECT 'phased period key outside the plan year', CAST(x.plan_fact_key AS nvarchar(20))
FROM dw.fact_plan_phased AS x
WHERE x.period_key <> CAST(LEFT(x.financial_year, 4) AS int) * 100 + x.period_no
UNION ALL
SELECT 'administration rows are not phased with their flag', 'none'
WHERE EXISTS (SELECT 1 FROM dw.fact_plan WHERE is_part_of_other_measure = 1)
  AND NOT EXISTS (SELECT 1 FROM dw.fact_plan_phased WHERE is_part_of_other_measure = 1);
