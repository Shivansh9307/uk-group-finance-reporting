-- Independent of the model: the fact summed on the department of the current structure, named by the form the department
-- has now (dw.dim_department at current_form_key), for 2025-26, ten largest.
SELECT TOP (10) d.department_number, nm.department_name AS department, CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS outturn
FROM dw.fact_outturn AS f
JOIN dw.dim_period AS p ON p.period_key = f.period_key
JOIN dw.current_structure_department AS d ON d.department_key = f.current_department_key
JOIN dw.dim_department AS nm ON nm.department_key = d.current_form_key
WHERE p.financial_year = '2025-26'
GROUP BY d.department_number, nm.department_name
ORDER BY SUM(f.amount_delta) DESC;
