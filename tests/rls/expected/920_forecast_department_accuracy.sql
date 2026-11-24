-- requires: dw.forecast_accuracy
-- Independent of the model views: dw.forecast_accuracy, the department of the current structure found from the number in the department
-- group's code through dw.department_reported_number, and only the departments that the user map gives the user.
WITH a AS (
    SELECT r.current_department_key AS dept, x.full_year_abs_error, x.full_year_abs_outturn
    FROM dw.forecast_accuracy AS x
    JOIN dw.department_reported_number AS r ON r.reported_department_number = SUBSTRING(x.department_group_code, 4, 3)
    WHERE x.method = 'department'
)
SELECT d.department_name AS department, COUNT_BIG(*) AS cells,
       CAST(SUM(a.full_year_abs_error) AS decimal(38, 4)) AS abs_error,
       CAST(SUM(a.full_year_abs_outturn) AS decimal(38, 4)) AS abs_outturn,
       CAST(SUM(CAST(a.full_year_abs_error AS decimal(38, 10))) / SUM(CAST(a.full_year_abs_outturn AS decimal(38, 10))) AS decimal(38, 10)) AS wape
FROM a
JOIN dw.dim_department AS d ON d.department_key = a.dept
WHERE d.department_number IN (SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user})
GROUP BY d.department_name
ORDER BY department;
