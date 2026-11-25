-- requires: dw.allocation_pool, dw.fact_allocation, audit.allocation_participation, dw.dim_department
-- Independent of the model views: the pool and the allocated amounts by year from their base tables, the weights added again from the
-- full-time equivalent, the gap as their difference, and the coverage counted from the participation table and the department
-- dimension (not read from the summary table the model reads). The ratios are worked in float in this query only (decimal division would keep six
-- decimals and hide an error in the model's ten) and cast to ten decimals. weights_off_by_ppm is the distance of the sum of the weights from 1 in parts per
-- million, rounded: the true sum is within 1e-9 of 1, so it is 0, and a weight sum of 0.9999 would give 100 and fail the comparison.
WITH f AS (
    SELECT financial_year, SUM(CAST(allocated_amount AS decimal(38, 4))) AS allocated, SUM(CAST(rounding_adjustment AS decimal(38, 4))) AS rounding,
           COUNT(*) AS taking_part, SUM(CAST(avg_fte AS float)) AS fte_total
    FROM dw.fact_allocation GROUP BY financial_year
),
w AS (
    SELECT g.financial_year, SUM(CAST(g.avg_fte AS float) / f.fte_total) AS weights
    FROM dw.fact_allocation AS g JOIN f ON f.financial_year = g.financial_year GROUP BY g.financial_year
),
l AS (
    SELECT financial_year, COUNT(*) AS left_out, SUM(CAST(avg_fte AS float)) AS left_fte
    FROM audit.allocation_participation WHERE status = 'too_few_months' GROUP BY financial_year
),
a AS (
    SELECT financial_year, SUM(CAST(avg_fte AS float)) AS all_fte, COUNT(*) AS with_data
    FROM audit.allocation_participation GROUP BY financial_year
)
SELECT p.financial_year,
       CAST(p.pool_amount AS decimal(38, 4)) AS pool,
       f.allocated AS allocated,
       CAST(f.allocated - p.pool_amount AS decimal(38, 4)) AS gap,
       f.rounding AS rounding,
       CAST(w.weights AS decimal(38, 10)) AS weights,
       CAST(ROUND(ABS(w.weights - 1) * 1000000, 0) AS decimal(38, 0)) AS weights_off_by_ppm,
       CAST(f.taking_part AS bigint) AS taking_part,
       CAST(COALESCE(l.left_out, 0) AS bigint) AS left_out,
       CAST(COALESCE(l.left_fte, 0) / a.all_fte AS decimal(38, 10)) AS left_out_share,
       CAST((SELECT COUNT(*) FROM dw.dim_department AS d
             WHERE d.is_current = 1 AND d.member_type = 'Department' AND d.department_key <> p.pool_department_key) - a.with_data AS bigint) AS no_data
FROM dw.allocation_pool AS p
JOIN f ON f.financial_year = p.financial_year
JOIN w ON w.financial_year = p.financial_year
JOIN a ON a.financial_year = p.financial_year
LEFT JOIN l ON l.financial_year = p.financial_year
ORDER BY p.financial_year;
