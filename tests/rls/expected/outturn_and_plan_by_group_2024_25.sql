-- Independent of the model: the outturn of the user's departments in 2024-25 by the group of the line (the bridge), and
-- the plan of 2024-25 by group for the groups whose departments the user holds in full.
WITH visible AS (
    SELECT g.sr_group_key
    FROM dw.dim_sr_group AS g
    WHERE EXISTS (SELECT 1 FROM authored.department_sr_group AS a
                  WHERE a.sr_group_code = g.sr_group_code AND a.basis IN ('current', 'pre2023_as_reported'))
      AND NOT EXISTS (SELECT 1 FROM authored.department_sr_group AS a
                      WHERE a.sr_group_code = g.sr_group_code AND a.basis IN ('current', 'pre2023_as_reported')
                        AND NOT EXISTS (SELECT 1 FROM synthetic.user_department AS x
                                        WHERE x.user_principal_name = {user} AND x.department_number = a.department_number))
), o AS (
    SELECT b.sr_group_key, SUM(f.amount_delta) AS outturn
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    JOIN dw.dim_segment AS s ON s.segment_key = f.segment_key
    JOIN dw.outturn_sr_group_bridge AS b ON b.organisation_key = f.organisation_key AND b.sub_segment_code = s.sub_segment_code
    JOIN dw.current_structure_department AS d ON d.department_key = f.current_department_key
    WHERE p.financial_year = '2024-25' AND d.department_number IN (SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user})
    GROUP BY b.sr_group_key
), pl AS (
    SELECT sr_group_key, SUM(amount) AS [plan]
    FROM dw.fact_plan
    WHERE financial_year = '2024-25' AND is_part_of_other_measure = 0 AND sr_group_key IN (SELECT sr_group_key FROM visible)
    GROUP BY sr_group_key
)
SELECT g.sr_group_name AS [Spending Review Group], CAST(o.outturn AS decimal(38, 4)) AS outturn,
       CAST(pl.[plan] AS decimal(38, 4)) AS [plan]
FROM dw.dim_sr_group AS g
LEFT JOIN o ON o.sr_group_key = g.sr_group_key
LEFT JOIN pl ON pl.sr_group_key = g.sr_group_key
WHERE o.sr_group_key IS NOT NULL OR pl.sr_group_key IS NOT NULL
ORDER BY g.sr_group_name;
