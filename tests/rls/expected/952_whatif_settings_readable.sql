-- requires: synthetic.whatif_parameter, dw.fact_allocation, dw.dim_department, synthetic.user_department
-- Independent of the model views: the rows of the synthetic table, the pay award of the default setting as a ratio, and the 2025-26
-- allocation to the user's own departments times one plus that pay award (NULL when the user has no allocation).
WITH a AS (
    SELECT SUM(CAST(f.allocated_amount AS decimal(38, 10))) AS allocated
    FROM dw.fact_allocation AS f
    JOIN dw.dim_department AS d ON d.department_key = f.department_key
    WHERE f.financial_year = '2025-26'
      AND d.department_number IN (SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user})
)
SELECT (SELECT COUNT_BIG(*) FROM synthetic.whatif_parameter) AS settings,
       (SELECT CAST(pay_award_pct / 100 AS decimal(38, 10)) FROM synthetic.whatif_parameter WHERE is_default = 1) AS pay_award,
       CAST(a.allocated * (1 + (SELECT pay_award_pct / 100 FROM synthetic.whatif_parameter WHERE is_default = 1)) AS decimal(38, 10)) AS whatif_allocated_2025_26
FROM a;
