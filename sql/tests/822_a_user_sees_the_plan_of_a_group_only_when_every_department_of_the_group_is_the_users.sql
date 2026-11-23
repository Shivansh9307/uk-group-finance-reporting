-- test: the groups whose plan a user may see are exactly those with at least one department member all of whose department numbers (authored/department_sr_group.csv, basis current or pre2023_as_reported) are among the user's departments, recomputed from the authored text table with a different query; a group with no department member is never visible
WITH members AS (
    SELECT DISTINCT a.sr_group_code, a.department_number
    FROM authored.department_sr_group AS a
    WHERE a.basis IN ('current', 'pre2023_as_reported')
), users AS (
    SELECT DISTINCT user_principal_name FROM synthetic.user_department
), should AS (
    SELECT u.user_principal_name, g.sr_group_key
    FROM users AS u
    CROSS JOIN dw.dim_sr_group AS g
    WHERE EXISTS (SELECT 1 FROM members AS m WHERE m.sr_group_code = g.sr_group_code)
      AND NOT EXISTS (SELECT 1 FROM members AS m
                      WHERE m.sr_group_code = g.sr_group_code
                        AND NOT EXISTS (SELECT 1 FROM synthetic.user_department AS x
                                        WHERE x.user_principal_name = u.user_principal_name
                                          AND x.department_number = m.department_number))
), actual AS (
    SELECT user_principal_name, sr_group_key FROM dw.v_model_user_plan_group
)
SELECT 'in the view and not by the rule' AS problem, a.user_principal_name, a.sr_group_key
FROM actual AS a
WHERE NOT EXISTS (SELECT 1 FROM should AS s WHERE s.user_principal_name = a.user_principal_name AND s.sr_group_key = a.sr_group_key)
UNION ALL
SELECT 'by the rule and not in the view', s.user_principal_name, s.sr_group_key
FROM should AS s
WHERE NOT EXISTS (SELECT 1 FROM actual AS a WHERE s.user_principal_name = a.user_principal_name AND s.sr_group_key = a.sr_group_key)
UNION ALL
SELECT 'a group with no department member is visible', a.user_principal_name, a.sr_group_key
FROM actual AS a JOIN dw.dim_sr_group AS g ON g.sr_group_key = a.sr_group_key
WHERE g.member_type IN ('plan_only', 'non_department', 'outturn_only')
UNION ALL
SELECT 'a user is in the view twice for one group', user_principal_name, sr_group_key
FROM actual GROUP BY user_principal_name, sr_group_key HAVING COUNT(*) > 1;
