-- requires: dw.fact_allocation, dw.allocation_pool
-- Independent of the model views: by year, the sum of pool times stored weight with each product held to four decimals (plain form, as
-- the engine holds a product with a fixed-decimal amount), the sum of the stored allocated amounts (rewrite) and the pool.
WITH x AS (
    SELECT f.financial_year,
           SUM(ROUND(CAST(p.pool_amount AS decimal(38, 10)) * CAST(f.weight AS decimal(38, 10)), 4)) AS allocated_naive,
           SUM(CAST(f.allocated_amount AS decimal(38, 10))) AS allocated_rewrite,
           MAX(CAST(p.pool_amount AS decimal(38, 10))) AS pool
    FROM dw.fact_allocation AS f
    JOIN dw.allocation_pool AS p ON p.pool_key = f.pool_key
    GROUP BY f.financial_year
)
SELECT financial_year, allocated_naive, allocated_rewrite, pool, allocated_rewrite - allocated_naive AS difference
FROM x ORDER BY financial_year;
