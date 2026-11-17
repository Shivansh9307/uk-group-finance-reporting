-- test: every plan line maps to a Spending Review group or is explicitly plan-only, non-department or combined pre-2023; nothing is unmapped, and every map target is a member of dw.dim_sr_group of the same type
SELECT 'estimates' AS source, edition, row_label_clean AS name, 'line has no entry in stg.plan_name_map' AS problem
FROM stg.plan_estimates_line WHERE row_kind = 'line' AND target_name IS NULL
GROUP BY edition, row_label_clean
UNION ALL
SELECT 'pesa', edition, row_label_clean, 'line has no entry in stg.plan_name_map'
FROM stg.plan_pesa_line WHERE row_kind = 'line' AND target_name IS NULL
GROUP BY edition, row_label_clean
UNION ALL
SELECT 'oscar', year_short_name, sr_group_name, 'SR group has no entry in stg.plan_name_map'
FROM raw.plan_oscar AS o
WHERE NOT EXISTS (SELECT 1 FROM stg.plan_name_map AS m WHERE m.name_family = 'oscar_extract' AND m.plan_name = o.sr_group_name)
GROUP BY year_short_name, sr_group_name
UNION ALL
SELECT 'map', m.name_family, m.plan_name, 'target is not in dw.dim_sr_group with the same type'
FROM stg.plan_name_map AS m
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_sr_group AS g WHERE g.sr_group_name = m.target_name AND g.member_type = m.target_type)
UNION ALL
SELECT 'map', name_family, plan_name, 'line_role must be whole, part or component'
FROM stg.plan_name_map WHERE line_role NOT IN ('whole', 'part', 'component')
UNION ALL
SELECT 'fact', NULL, CAST(plan_fact_key AS nvarchar(20)), 'fact row has no Spending Review group'
FROM dw.fact_plan AS f
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_sr_group AS g WHERE g.sr_group_key = f.sr_group_key);
