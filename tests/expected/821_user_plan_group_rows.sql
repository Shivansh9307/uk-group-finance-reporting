-- Independent of the model's view: the rule written as "a group with at least one department member and no member
-- outside the user's departments", from the authored text table of the group map.
WITH members AS (
    SELECT DISTINCT a.sr_group_code, a.department_number
    FROM authored.department_sr_group AS a
    WHERE a.basis IN ('current', 'pre2023_as_reported')
)
SELECT u.user_principal_name, g.sr_group_key
FROM (SELECT DISTINCT user_principal_name FROM synthetic.user_department) AS u
CROSS JOIN dw.dim_sr_group AS g
WHERE EXISTS (SELECT 1 FROM members AS m WHERE m.sr_group_code = g.sr_group_code)
  AND NOT EXISTS (SELECT 1 FROM members AS m
                  WHERE m.sr_group_code = g.sr_group_code
                    AND NOT EXISTS (SELECT 1 FROM synthetic.user_department AS x
                                    WHERE x.user_principal_name = u.user_principal_name
                                      AND x.department_number = m.department_number))
ORDER BY u.user_principal_name, g.sr_group_key;
