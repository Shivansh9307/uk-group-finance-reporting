-- test: the FY2022-23 plan is published for BEIS, DCMS and DIT as one group, so the outturn of the departments 013, 048 and 084 as reported is in that group (in the plan-basis table and in the model's outturn view), nothing else is regrouped, and the group has an outturn wherever it has a plan (with the outturn on the current structure it had a plan and no outturn)
WITH combined AS (
    SELECT sr_group_key FROM dw.dim_sr_group WHERE member_type = 'combined_pre_2023'
)
SELECT 'FY2022-23 line of a reported department 013, 048 or 084 outside the combined group' AS problem, CAST(COUNT(*) AS nvarchar(40)) AS detail, CAST(NULL AS nvarchar(40)) AS detail2
FROM dw.outturn_plan_line AS l
WHERE l.financial_year = '2022-23' AND l.reported_department_number IN ('013', '048', '084')
  AND l.plan_sr_group_key NOT IN (SELECT sr_group_key FROM combined)
HAVING COUNT(*) > 0
UNION ALL
SELECT 'line of another department or year in the combined group', CAST(COUNT(*) AS nvarchar(40)), NULL
FROM dw.outturn_plan_line AS l
WHERE l.plan_sr_group_key IN (SELECT sr_group_key FROM combined)
  AND NOT (l.financial_year = '2022-23' AND l.reported_department_number IN ('013', '048', '084'))
HAVING COUNT(*) > 0
UNION ALL
SELECT 'line regrouped although no rule applies', CAST(COUNT(*) AS nvarchar(40)), NULL
FROM dw.outturn_plan_line AS l
WHERE l.plan_sr_group_key <> l.sr_group_key
  AND NOT (l.financial_year = '2022-23' AND l.reported_department_number IN ('013', '048', '084'))
HAVING COUNT(*) > 0
UNION ALL
-- the model's outturn view: the combined group holds exactly the FY2022-23 outturn of those departments, recomputed from the fact
SELECT 'model outturn view differs from the fact for the combined group', CONCAT(v.s, ' against ', f.s), NULL
FROM (SELECT SUM(CAST(o.amount_delta AS decimal(38, 4))) AS s
      FROM dw.v_model_fact_outturn AS o
      JOIN dw.dim_period AS p ON p.period_key = o.period_key
      WHERE o.sr_group_key IN (SELECT sr_group_key FROM combined) AND p.financial_year = '2022-23') AS v
CROSS JOIN (SELECT SUM(CAST(x.amount_delta AS decimal(38, 4))) AS s
            FROM dw.fact_outturn AS x
            JOIN dw.dim_period AS p ON p.period_key = x.period_key
            JOIN dw.dim_department AS d ON d.department_key = x.department_key
            WHERE p.financial_year = '2022-23' AND d.department_number IN ('013', '048', '084')) AS f
WHERE v.s <> f.s OR v.s IS NULL
UNION ALL
SELECT 'model outturn view holds the combined group outside FY2022-23', CAST(COUNT_BIG(*) AS nvarchar(40)), NULL
FROM dw.v_model_fact_outturn AS o
JOIN dw.dim_period AS p ON p.period_key = o.period_key
WHERE o.sr_group_key IN (SELECT sr_group_key FROM combined) AND p.financial_year <> '2022-23'
HAVING COUNT_BIG(*) > 0
UNION ALL
-- a plan row of the group for a year and a measure has outturn on that measure
SELECT 'combined group has a plan and no outturn', CONCAT(p.financial_year, ' ', p.measure), NULL
FROM dw.fact_plan AS p
WHERE p.sr_group_key IN (SELECT sr_group_key FROM combined) AND p.financial_year = '2022-23'
  AND p.measure IN ('RDEL_EX_DEPN', 'CDEL', 'RAME', 'CAME') AND p.is_part_of_other_measure = 0
  AND NOT EXISTS (SELECT 1 FROM dw.outturn_plan_basis_inyear AS b
                  WHERE b.sr_group_key = p.sr_group_key AND b.financial_year = p.financial_year AND b.measure = p.measure
                    AND b.is_year_end_release = 1 AND b.amount <> 0);
