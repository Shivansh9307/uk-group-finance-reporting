-- test: every SR group name in the OSCAR plan rows has an entry in the plan name map
-- marker: localdata
-- requires: raw.plan_oscar, stg.plan_name_map
SELECT 'oscar' AS source, year_short_name, sr_group_name, 'SR group has no entry in stg.plan_name_map' AS problem
FROM raw.plan_oscar AS o
WHERE NOT EXISTS (SELECT 1 FROM stg.plan_name_map AS m WHERE m.name_family = 'oscar_extract' AND m.plan_name = o.sr_group_name)
GROUP BY year_short_name, sr_group_name;
