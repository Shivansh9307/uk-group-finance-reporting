-- requires: dw.fact_allocation, dw.allocation_pool, dw.dim_department
-- Independent of the model views. The plain form is the pool times the stored weight (10 decimals), each product held to four
-- decimals as the engine holds a product with a fixed-decimal amount, and the rewrite is the stored allocated amount; the difference is
-- worked out here from the two, not copied.
WITH x AS (
    SELECT f.financial_year, d.department_number,
           ROUND(CAST(p.pool_amount AS decimal(38, 10)) * CAST(f.weight AS decimal(38, 10)), 4) AS allocated_naive,
           CAST(f.allocated_amount AS decimal(38, 10)) AS allocated_rewrite
    FROM dw.fact_allocation AS f
    JOIN dw.allocation_pool AS p ON p.pool_key = f.pool_key
    JOIN dw.dim_department AS d ON d.department_key = f.department_key
)
SELECT financial_year, department_number, allocated_naive, allocated_rewrite, allocated_rewrite - allocated_naive AS difference
FROM x ORDER BY financial_year, department_number;
