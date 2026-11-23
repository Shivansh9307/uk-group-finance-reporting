-- Independent of the model: the year-end variance % of each Spending Review group on the DEL headline (the plan measures
-- resource DEL excluding depreciation and capital DEL), then RANK() over the groups of the year, largest first. Outturn on
-- the plan's basis is the in-year basis table at the closing release of the year, over the same two measures and only
-- where the group has a plan row for the measure; the plan is the sum of those plan rows. A year to date at the end of
-- the year is the whole year, so the one-year grid at period 12 is the 2024-25 rows of the three-year grid. Variance % is
-- (basis - plan) over the absolute plan, missing where the plan is zero, in parts per million. Both ranks equal it.
WITH basis AS (
    SELECT b.financial_year AS fy, b.sr_group_key, SUM(b.amount) AS basis
    FROM dw.outturn_plan_basis_inyear AS b
    WHERE b.financial_year IN ('2023-24', '2024-25', '2025-26')
      AND b.measure IN ('RDEL_EX_DEPN', 'CDEL')
      AND b.release_key = (SELECT MAX(r.release_key) FROM dw.dim_release AS r WHERE r.financial_year = b.financial_year)
      AND EXISTS (SELECT 1 FROM dw.fact_plan AS p
                  WHERE p.financial_year = b.financial_year AND p.sr_group_key = b.sr_group_key AND p.measure = b.measure
                    AND p.is_part_of_other_measure = 0)
    GROUP BY b.financial_year, b.sr_group_key
), pl AS (
    SELECT p.financial_year AS fy, p.sr_group_key, SUM(p.amount) AS plan_amount
    FROM dw.fact_plan AS p
    WHERE p.financial_year IN ('2023-24', '2024-25', '2025-26') AND p.is_part_of_other_measure = 0
      AND p.measure IN ('RDEL_EX_DEPN', 'CDEL')
    GROUP BY p.financial_year, p.sr_group_key
), v AS (
    SELECT b.fy, b.sr_group_key,
           CAST(b.basis - p.plan_amount AS decimal(38, 10)) * 1000000 / NULLIF(ABS(CAST(p.plan_amount AS decimal(38, 10))), 0) AS variance_pct
    FROM basis AS b JOIN pl AS p ON p.fy = b.fy AND p.sr_group_key = b.sr_group_key
), ranked AS (
    SELECT v.fy, g.sr_group_name, v.variance_pct,
           RANK() OVER (PARTITION BY v.fy ORDER BY v.variance_pct DESC) AS group_rank
    FROM v
    JOIN dw.dim_sr_group AS g ON g.sr_group_key = v.sr_group_key
    WHERE v.variance_pct IS NOT NULL
), grids AS (
    SELECT 'one_year_period_12' AS grid, fy, sr_group_name, variance_pct, group_rank FROM ranked WHERE fy = '2024-25'
    UNION ALL
    SELECT 'three_years', fy, sr_group_name, variance_pct, group_rank FROM ranked
)
SELECT grid, fy AS financial_year, sr_group_name AS spending_review_group,
       CAST(variance_pct AS decimal(38, 6)) AS ytd_variance_ppm,
       group_rank AS rank_naive, group_rank AS rank_rewrite, CAST(0 AS int) AS rank_difference
FROM grids
ORDER BY grid, fy, sr_group_name;
