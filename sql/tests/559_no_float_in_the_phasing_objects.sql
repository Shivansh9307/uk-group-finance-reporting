-- test: none of the tables of this feature has a float or real column, and every amount is decimal(19,4) and every share decimal(19,10)
SELECT 'floating point column' AS problem, s.name + '.' + t.name AS detail, c.name AS detail2, ty.name AS type_name
FROM sys.columns AS c
JOIN sys.tables AS t ON t.object_id = c.object_id
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE s.name + '.' + t.name IN ('stg.department_sr_group', 'dw.outturn_sr_group_bridge', 'dw.plan_measure_selection', 'dw.outturn_plan_line',
                                'dw.plan_phasing_profile', 'dw.fact_plan_phased', 'dw.outturn_plan_basis_inyear',
                                'dw.outturn_plan_basis_annual', 'audit.sr_group_bridge_summary', 'audit.plan_phasing_summary',
                                'audit.plan_basis_inyear_vs_annual', 'audit.sr_group_bridge_vs_bud')
  AND ty.name IN ('float', 'real', 'money', 'smallmoney')
UNION ALL
SELECT 'amount column is not decimal(19,4)', s.name + '.' + t.name, c.name, CONCAT(ty.name, '(', c.precision, ',', c.scale, ')')
FROM sys.columns AS c
JOIN sys.tables AS t ON t.object_id = c.object_id
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE s.name + '.' + t.name IN ('dw.outturn_plan_line', 'dw.fact_plan_phased', 'dw.outturn_plan_basis_inyear', 'dw.outturn_plan_basis_annual')
  AND c.name IN ('amount', 'amount_delta') AND NOT (ty.name = 'decimal' AND c.precision = 19 AND c.scale = 4)
UNION ALL
SELECT 'share column is not decimal(19,10)', s.name + '.' + t.name, c.name, CONCAT(ty.name, '(', c.precision, ',', c.scale, ')')
FROM sys.columns AS c
JOIN sys.tables AS t ON t.object_id = c.object_id
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE s.name + '.' + t.name IN ('dw.plan_phasing_profile', 'dw.fact_plan_phased')
  AND c.name = 'share' AND NOT (ty.name = 'decimal' AND c.precision = 19 AND c.scale = 10);
