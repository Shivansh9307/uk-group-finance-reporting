-- Independent of the model: the outturn fact summed on year and department number, for the departments the user map
-- names for the user. A user in no row of the map has no department and so no row.
SELECT p.financial_year AS [Financial Year], d.department_number AS [Department Number],
       CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS outturn
FROM dw.fact_outturn AS f
JOIN dw.dim_period AS p ON p.period_key = f.period_key
JOIN dw.current_structure_department AS d ON d.department_key = f.current_department_key
WHERE d.department_number IN (SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user})
GROUP BY p.financial_year, d.department_number
ORDER BY p.financial_year, d.department_number;
