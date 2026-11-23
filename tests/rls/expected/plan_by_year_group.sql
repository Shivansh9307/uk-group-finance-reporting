-- Independent of the model: the plan and the phased plan summed by year and group, for the groups whose departments the
-- user holds in full.
WITH visible AS (
    SELECT g.sr_group_key
    FROM dw.dim_sr_group AS g
    WHERE EXISTS (SELECT 1 FROM authored.department_sr_group AS a
                  WHERE a.sr_group_code = g.sr_group_code AND a.basis IN ('current', 'pre2023_as_reported'))
      AND NOT EXISTS (SELECT 1 FROM authored.department_sr_group AS a
                      WHERE a.sr_group_code = g.sr_group_code AND a.basis IN ('current', 'pre2023_as_reported')
                        AND NOT EXISTS (SELECT 1 FROM synthetic.user_department AS x
                                        WHERE x.user_principal_name = {user} AND x.department_number = a.department_number))
), p AS (
    SELECT financial_year, sr_group_key, SUM(amount) AS [plan]
    FROM dw.fact_plan WHERE is_part_of_other_measure = 0 AND sr_group_key IN (SELECT sr_group_key FROM visible)
    GROUP BY financial_year, sr_group_key
), ph AS (
    SELECT d.financial_year, f.sr_group_key, SUM(f.amount) AS phased
    FROM dw.fact_plan_phased AS f JOIN dw.dim_period AS d ON d.period_key = f.period_key
    WHERE f.is_part_of_other_measure = 0 AND f.sr_group_key IN (SELECT sr_group_key FROM visible)
    GROUP BY d.financial_year, f.sr_group_key
)
SELECT p.financial_year AS [Financial Year], g.sr_group_name AS [Spending Review Group],
       CAST(p.[plan] AS decimal(38, 4)) AS [plan], CAST(ph.phased AS decimal(38, 4)) AS plan_phased
FROM p
JOIN dw.dim_sr_group AS g ON g.sr_group_key = p.sr_group_key
LEFT JOIN ph ON ph.financial_year = p.financial_year AND ph.sr_group_key = p.sr_group_key
ORDER BY p.financial_year, g.sr_group_name;
