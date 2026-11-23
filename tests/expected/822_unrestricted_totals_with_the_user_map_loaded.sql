-- Independent of the model: the facts summed on their own, and the rows of the synthetic table, with no join between them.
SELECT N'Outturn, all' AS name, CAST(SUM(amount_delta) AS decimal(38, 4)) AS value FROM dw.fact_outturn
UNION ALL
SELECT N'Plan, all', CAST(SUM(amount) AS decimal(38, 4)) FROM dw.fact_plan WHERE is_part_of_other_measure = 0
UNION ALL
SELECT N'Plan (phased), all', CAST(SUM(amount) AS decimal(38, 4)) FROM dw.fact_plan_phased WHERE is_part_of_other_measure = 0
UNION ALL
SELECT N'Fact Outturn rows', CAST(COUNT_BIG(*) AS decimal(38, 4)) FROM dw.fact_outturn
UNION ALL
SELECT N'Fact Plan rows', CAST(COUNT_BIG(*) AS decimal(38, 4)) FROM dw.fact_plan
UNION ALL
SELECT N'User Department (synthetic) rows', CAST(COUNT_BIG(*) AS decimal(38, 4)) FROM synthetic.user_department
UNION ALL
SELECT N'User Plan Group (synthetic) rows', CAST(COUNT_BIG(*) AS decimal(38, 4))
FROM (
    SELECT u.user_principal_name, g.sr_group_key
    FROM (SELECT DISTINCT user_principal_name FROM synthetic.user_department) AS u
    CROSS JOIN dw.dim_sr_group AS g
    WHERE EXISTS (SELECT 1 FROM authored.department_sr_group AS a WHERE a.sr_group_code = g.sr_group_code AND a.basis IN ('current', 'pre2023_as_reported'))
      AND NOT EXISTS (SELECT 1 FROM authored.department_sr_group AS a
                      WHERE a.sr_group_code = g.sr_group_code AND a.basis IN ('current', 'pre2023_as_reported')
                        AND NOT EXISTS (SELECT 1 FROM synthetic.user_department AS x
                                        WHERE x.user_principal_name = u.user_principal_name AND x.department_number = a.department_number))
) AS v
UNION ALL
SELECT N'Users in the map', CAST(COUNT(DISTINCT user_principal_name) AS decimal(38, 4)) FROM synthetic.user_department
ORDER BY name;
