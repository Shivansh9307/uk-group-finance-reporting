-- test: nothing authored can reach a real total: the authored plan tables hold no amount columns, the plan dimensions hold no amounts, and the fact total of each grain equals the total of the published figures it comes from
SELECT s.name + '.' + t.name AS object_name, c.name AS detail, ty.name AS type_name, 'authored table has a numeric column' AS problem
FROM sys.columns AS c
JOIN sys.tables AS t ON t.object_id = c.object_id
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE s.name = 'authored' AND t.name IN ('plan_name_map', 'sr_group', 'plan_source')
  AND ty.name IN ('decimal', 'numeric', 'float', 'real', 'money', 'smallmoney', 'bigint')
UNION ALL
SELECT 'dw.' + t.name, c.name, NULL, 'dimension has an amount column'
FROM sys.columns AS c
JOIN sys.tables AS t ON t.object_id = c.object_id
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name = 'dw' AND t.name IN ('dim_sr_group', 'dim_plan_source', 'dim_plan_grain')
  AND c.name IN ('amount', 'amount_k', 'amount_total', 'value')
UNION ALL
SELECT 'grain A', NULL, CAST(SUM(amount) AS varchar(40)), 'fact total differs from stg.plan_oscar'
FROM dw.fact_plan WHERE grain_code = 'A'
HAVING SUM(amount) <> (SELECT COALESCE(SUM(amount), 0) FROM stg.plan_oscar)
UNION ALL
SELECT 'grain B and C', NULL, CAST(SUM(amount) AS varchar(40)), 'fact total differs from the final-plan Estimates lines'
FROM dw.fact_plan WHERE grain_code IN ('B', 'C')
HAVING SUM(amount) <> (SELECT COALESCE(SUM(l.amount_k), 0) FROM stg.plan_estimates_line AS l
                       WHERE l.is_final_plan = 1 AND l.row_kind = 'line' AND l.line_role <> 'component'
                         AND l.measure IN ('RDEL_EX_DEPN', 'CDEL') AND l.amount_k IS NOT NULL);
