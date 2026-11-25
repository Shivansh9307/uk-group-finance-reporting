-- requires: dw.allocation_pool, dw.fact_allocation, dw.dim_department, synthetic.user_department
-- Independent of the model views. The pool is returned to every user (neither role filters it); the allocated amount is the sum over
-- the user's own departments; the gap is blank for every user of a role, because none sees every participating department. Every year
-- of the rule is listed, because its pool is visible.
WITH me AS (
    SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user}
),
a AS (
    SELECT f.financial_year, SUM(CAST(f.allocated_amount AS decimal(38, 4))) AS allocated
    FROM dw.fact_allocation AS f
    JOIN dw.dim_department AS d ON d.department_key = f.department_key
    WHERE d.department_number IN (SELECT department_number FROM me)
    GROUP BY f.financial_year
),
p AS (
    SELECT pl.financial_year, CAST(pl.pool_amount AS decimal(38, 4)) AS pool
    FROM dw.allocation_pool AS pl
)
SELECT COALESCE(p.financial_year, a.financial_year) AS financial_year, p.pool, a.allocated, CAST(NULL AS decimal(38, 4)) AS gap
FROM p FULL JOIN a ON a.financial_year = p.financial_year
ORDER BY financial_year;
