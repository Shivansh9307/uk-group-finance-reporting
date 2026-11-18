-- Independent of the model. Below the grain of a plan the number of non-blank cells is 0 by the rule of the guard (a
-- plan figure there would be a number the source never gave). At the grain it is the number of distinct keys the plan
-- has, from dw.fact_plan, that also exist as a member of the dimension the model cuts by.
WITH y AS (SELECT '2019-20' AS financial_year UNION ALL SELECT '2024-25'),
below AS (
    SELECT l.level, y.financial_year AS [year], 0 AS cells
    FROM (VALUES (N'month'), (N'sub-segment'), (N'economic category'), (N'organisation version'), (N'department'), (N'data quality issue')) AS l(level)
    CROSS JOIN y
    UNION ALL
    SELECT l.level, '2024-25', 0
    FROM (VALUES (N'organisation code'), (N'control budget detail'), (N'economic budget')) AS l(level)
),
a_year AS (SELECT * FROM dw.fact_plan WHERE financial_year = '2019-20' AND grain_code = 'A' AND is_part_of_other_measure = 0)
SELECT level, [year], CAST(cells AS int) AS cells FROM below
UNION ALL
SELECT N'organisation code', '2019-20', CAST(COUNT(DISTINCT p.organisation_code) AS int)
FROM a_year AS p WHERE EXISTS (SELECT 1 FROM dw.dim_organisation AS o WHERE o.organisation_code = p.organisation_code)
UNION ALL
SELECT N'control budget detail', '2019-20', CAST(COUNT(DISTINCT p.control_budget_detail) AS int)
FROM a_year AS p WHERE EXISTS (SELECT 1 FROM dw.dim_control_budget AS c WHERE c.control_budget_detail_code = p.control_budget_detail)
UNION ALL
SELECT N'economic budget', '2019-20', CAST(COUNT(DISTINCT CASE WHEN p.economic_budget = 'n/a' THEN 'NA' ELSE p.economic_budget END) AS int)
FROM a_year AS p WHERE EXISTS (SELECT 1 FROM dw.dim_account AS a WHERE a.economic_budget = CASE WHEN p.economic_budget = 'n/a' THEN 'NA' ELSE p.economic_budget END)
UNION ALL
SELECT N'financial year', y.financial_year, 1 FROM y
UNION ALL
SELECT N'spending review group', f.financial_year, CAST(COUNT(DISTINCT f.sr_group_key) AS int)
FROM dw.fact_plan AS f WHERE f.financial_year IN ('2019-20', '2024-25') AND f.is_part_of_other_measure = 0 GROUP BY f.financial_year
UNION ALL
SELECT N'plan source', f.financial_year, CAST(COUNT(DISTINCT f.plan_source_key) AS int)
FROM dw.fact_plan AS f WHERE f.financial_year IN ('2019-20', '2024-25') AND f.is_part_of_other_measure = 0 GROUP BY f.financial_year
UNION ALL
SELECT N'plan measure', f.financial_year, CAST(COUNT(DISTINCT f.measure) AS int)
FROM dw.fact_plan AS f WHERE f.financial_year IN ('2019-20', '2024-25') GROUP BY f.financial_year
ORDER BY [year], level;
