-- requires: dw.allocation_pool, dw.fact_allocation, dw.dim_department, synthetic.user_department
-- Independent of the model views. A user sees the pool of a year only through a department that takes part in that year: the years listed are
-- those in which the user has an allocation, with the allocated amount summed over the user's own departments and the year's pool beside it.
-- The gap is blank for every user of a role, because none sees every participating department. A user in no row of the map, and a user
-- who holds only departments that take no part (the Cabinet Office, the pool's own department), have no row at all.
WITH me AS (
    SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user}
),
a AS (
    SELECT f.rule_id, f.financial_year, SUM(CAST(f.allocated_amount AS decimal(38, 4))) AS allocated
    FROM dw.fact_allocation AS f
    JOIN dw.dim_department AS d ON d.department_key = f.department_key
    WHERE d.department_number IN (SELECT department_number FROM me)
    GROUP BY f.rule_id, f.financial_year
)
SELECT a.financial_year, CAST(p.pool_amount AS decimal(38, 4)) AS pool, a.allocated, CAST(NULL AS decimal(38, 4)) AS gap
FROM a
JOIN dw.allocation_pool AS p ON p.rule_id = a.rule_id AND p.financial_year = a.financial_year
ORDER BY a.financial_year;
