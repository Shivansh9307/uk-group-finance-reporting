-- requires: dw.forecast_pay_accuracy, dw.forecast_fte_cost_input
-- Independent of the model views: the FTE x cost rows of dw.forecast_pay_accuracy by the department of the current structure, with the
-- workforce paybill of the last actual month (pounds, divided by 1,000) and the pay line of that month from dw.forecast_fte_cost_input.
WITH a AS (
    SELECT r.current_department_key AS dept, x.financial_year, x.return_no, x.department_group_code
    FROM dw.forecast_pay_accuracy AS x
    JOIN dw.department_reported_number AS r ON r.reported_department_number = SUBSTRING(x.department_group_code, 4, 3)
    WHERE x.method = 'fte_cost'
)
SELECT d.department_name AS department, COUNT_BIG(*) AS fte_cost_cells,
       CAST(SUM(CASE WHEN i.pay_month_n > 0 THEN i.workforce_paybill_gbp / 1000 END) / SUM(CASE WHEN i.pay_month_n > 0 THEN i.pay_month_n END) AS decimal(38, 10)) AS pay_cover
FROM a
JOIN dw.forecast_fte_cost_input AS i ON i.financial_year = a.financial_year AND i.return_no = a.return_no AND i.department_group_code = a.department_group_code
JOIN dw.dim_department AS d ON d.department_key = a.dept
WHERE d.department_number IN (SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user})
GROUP BY d.department_name
ORDER BY department;
