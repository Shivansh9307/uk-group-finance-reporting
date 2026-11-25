-- requires: dw.fact_allocation, dw.dim_department, synthetic.user_department
-- Independent of the model views: the allocation fact of 2025-26 for the departments that the user map gives the user. The weight is worked
-- out again as the department's average full-time equivalent over the sum of all the participants of the year (not only the user's).
WITH f AS (
    SELECT d.department_number, f.avg_fte, f.allocated_amount, f.paybill_annualised,
           SUM(CAST(f.avg_fte AS decimal(38, 12))) OVER (PARTITION BY f.rule_id, f.financial_year) AS fte_total
    FROM dw.fact_allocation AS f
    JOIN dw.dim_department AS d ON d.department_key = f.department_key
    WHERE f.financial_year = '2025-26'
)
SELECT f.department_number,
       CAST(CAST(f.avg_fte AS decimal(38, 12)) / f.fte_total AS decimal(38, 10)) AS [weight],
       CAST(f.allocated_amount AS decimal(38, 4)) AS allocated,
       CAST(f.paybill_annualised AS decimal(38, 4)) AS paybill
FROM f
WHERE f.department_number IN (SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user})
ORDER BY f.department_number;
