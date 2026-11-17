-- test: CLG085.GROUP maps to two Spending Review groups, so the organisation and not the department group keys the SR group
-- marker: localdata
-- requires: stg.bud_sr_group_by_organisation, stg.bud_department_group_map
SELECT N'CLG085.GROUP SR groups in the organisation map (latest vintage)' AS problem,
       CAST(COUNT(DISTINCT sr_group_code) AS nvarchar(200)) AS detail
FROM stg.bud_sr_group_by_organisation
WHERE department_group_code = N'CLG085.GROUP' AND is_latest_vintage = 1
HAVING COUNT(DISTINCT sr_group_code) <> 2
UNION ALL
SELECT N'CLG085.GROUP SR groups in the department group map (latest vintage)',
       CAST(COUNT(DISTINCT sr_group_code) AS nvarchar(200))
FROM stg.bud_department_group_map
WHERE department_group_code = N'CLG085.GROUP' AND is_latest_vintage = 1
HAVING COUNT(DISTINCT sr_group_code) <> 2
UNION ALL
SELECT N'CLG085.GROUP SR groups are not the two expected', STRING_AGG(sr_group_name, N' | ') WITHIN GROUP (ORDER BY sr_group_name)
FROM (SELECT DISTINCT sr_group_name FROM stg.bud_sr_group_by_organisation
      WHERE department_group_code = N'CLG085.GROUP' AND is_latest_vintage = 1) AS x
HAVING STRING_AGG(sr_group_name, N' | ') WITHIN GROUP (ORDER BY sr_group_name) <> N'CLG Communities | CLG Local Government';
