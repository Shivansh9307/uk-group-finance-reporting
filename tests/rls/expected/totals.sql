-- Independent of the model: the outturn of the user's departments, and the plan and the phased plan of the groups whose
-- departments the user holds in full (a group with a department member and no member outside the user's departments).
-- With no department and no group every column is NULL: one row of blanks.
WITH visible AS (
    SELECT g.sr_group_key
    FROM dw.dim_sr_group AS g
    WHERE EXISTS (SELECT 1 FROM authored.department_sr_group AS a
                  WHERE a.sr_group_code = g.sr_group_code AND a.basis IN ('current', 'pre2023_as_reported'))
      AND NOT EXISTS (SELECT 1 FROM authored.department_sr_group AS a
                      WHERE a.sr_group_code = g.sr_group_code AND a.basis IN ('current', 'pre2023_as_reported')
                        AND NOT EXISTS (SELECT 1 FROM synthetic.user_department AS x
                                        WHERE x.user_principal_name = {user} AND x.department_number = a.department_number))
)
SELECT
    CAST((SELECT SUM(f.amount_delta)
          FROM dw.fact_outturn AS f
          JOIN dw.current_structure_department AS d ON d.department_key = f.current_department_key
          WHERE d.department_number IN (SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user})) AS decimal(38, 4)) AS outturn,
    CAST((SELECT SUM(p.amount) FROM dw.fact_plan AS p
          WHERE p.is_part_of_other_measure = 0 AND p.sr_group_key IN (SELECT sr_group_key FROM visible)) AS decimal(38, 4)) AS [plan],
    CAST((SELECT SUM(p.amount) FROM dw.fact_plan_phased AS p
          WHERE p.is_part_of_other_measure = 0 AND p.sr_group_key IN (SELECT sr_group_key FROM visible)) AS decimal(38, 4)) AS plan_phased;
