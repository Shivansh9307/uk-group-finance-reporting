-- Independent of the model: the year-end variance % of each Spending Review group, then RANK() over the groups of the
-- year, largest first. Outturn on the plan's basis is the in-year basis table at the closing release of the year, summed
-- over the measures that have a plan row in the year and group, administration left out; the plan is the sum of the plan
-- rows that are not part of another measure. A year to date at the end of the year is the whole year. Variance % is
-- (basis - plan) over the absolute plan, missing where the plan is zero, in parts per million (the numerator is scaled
-- before the division, which keeps six decimals of the ppm).
WITH basis AS (
    SELECT b.financial_year AS fy, b.sr_group_key, SUM(b.amount) AS basis
    FROM dw.outturn_plan_basis_inyear AS b
    WHERE b.financial_year IN ('2023-24', '2024-25', '2025-26')
      AND b.measure NOT IN ('ADMIN', 'ADMIN_EX_DEPN')
      AND b.release_key = (SELECT MAX(r.release_key) FROM dw.dim_release AS r WHERE r.financial_year = b.financial_year)
      AND EXISTS (SELECT 1 FROM dw.fact_plan AS p
                  WHERE p.financial_year = b.financial_year AND p.sr_group_key = b.sr_group_key AND p.measure = b.measure
                    AND p.is_part_of_other_measure = 0)
    GROUP BY b.financial_year, b.sr_group_key
), pl AS (
    SELECT p.financial_year AS fy, p.sr_group_key, SUM(p.amount) AS plan_amount
    FROM dw.fact_plan AS p
    WHERE p.financial_year IN ('2023-24', '2024-25', '2025-26') AND p.is_part_of_other_measure = 0
    GROUP BY p.financial_year, p.sr_group_key
), v AS (
    SELECT b.fy, b.sr_group_key,
           CAST(b.basis - p.plan_amount AS decimal(38, 10)) * 1000000 / NULLIF(ABS(CAST(p.plan_amount AS decimal(38, 10))), 0) AS variance_pct
    FROM basis AS b JOIN pl AS p ON p.fy = b.fy AND p.sr_group_key = b.sr_group_key
)
SELECT v.fy AS [Financial Year], g.sr_group_name AS [Spending Review Group],
       CAST(v.variance_pct AS decimal(38, 6)) AS ytd_variance_ppm,
       CASE WHEN v.variance_pct IS NULL THEN NULL
            ELSE RANK() OVER (PARTITION BY v.fy ORDER BY CASE WHEN v.variance_pct IS NULL THEN 1 ELSE 0 END, v.variance_pct DESC) END AS group_rank
FROM v
JOIN dw.dim_sr_group AS g ON g.sr_group_key = v.sr_group_key
WHERE v.variance_pct IS NOT NULL
ORDER BY v.fy, g.sr_group_name;
