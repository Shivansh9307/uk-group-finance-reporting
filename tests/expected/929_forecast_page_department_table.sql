-- requires: dw.forecast_accuracy, dw.forecast_pay_accuracy, dw.forecast_fte_cost_input
-- Independent of the model views: the department of the current structure from the number in the group code through dw.department_reported_number.
-- The model's ratios agree with this query to within 0.000001 (the largest difference on these tests in evidence/model/dax_tests.csv is 0.00000099; the comparison tolerance is 0.0001): the SQL carries 10 decimal places, the agreement is to 6.
WITH m AS (
    SELECT r.reported_department_number AS num, r.current_department_key AS dept FROM dw.department_reported_number AS r
),
tot AS (
    SELECT m.dept, CAST(SUM(CAST(a.full_year_abs_error AS decimal(38, 10))) / SUM(CAST(a.full_year_abs_outturn AS decimal(38, 10))) AS decimal(38, 10)) AS wape,
           CAST(SUM(CASE WHEN a.is_flagged_return = 0 THEN CAST(a.full_year_abs_error AS decimal(38, 10)) END)
                / NULLIF(SUM(CASE WHEN a.is_flagged_return = 0 THEN CAST(a.full_year_abs_outturn AS decimal(38, 10)) END), 0) AS decimal(38, 10)) AS wape_excl
    FROM dw.forecast_accuracy AS a JOIN m ON m.num = SUBSTRING(a.department_group_code, 4, 3)
    WHERE a.method = 'department'
    GROUP BY m.dept
),
elig AS (
    SELECT m.dept, COUNT_BIG(*) AS n FROM dw.forecast_pay_accuracy AS a JOIN m ON m.num = SUBSTRING(a.department_group_code, 4, 3)
    WHERE a.method = 'department' AND a.return_no BETWEEN 1 AND 11 GROUP BY m.dept
),
cov AS (
    SELECT m.dept, COUNT_BIG(*) AS n FROM dw.forecast_pay_accuracy AS a JOIN m ON m.num = SUBSTRING(a.department_group_code, 4, 3)
    WHERE a.method = 'fte_cost' GROUP BY m.dept
),
cvr AS (
    SELECT m.dept, SUM(i.workforce_paybill_gbp / 1000) AS wf, SUM(i.pay_month_n) AS pay
    FROM dw.forecast_fte_cost_input AS i
    JOIN dw.forecast_pay_accuracy AS a ON a.financial_year = i.financial_year AND a.return_no = i.return_no
                                      AND a.department_group_code = i.department_group_code AND a.method = 'fte_cost'
    JOIN m ON m.num = SUBSTRING(i.department_group_code, 4, 3)
    WHERE i.pay_month_n > 0
    GROUP BY m.dept
)
SELECT d.department_name AS department, t.wape, t.wape_excl,
       CAST(CAST(c.n AS decimal(38, 10)) / e.n AS decimal(38, 10)) AS cell_coverage,
       CAST(v.wf / v.pay AS decimal(38, 10)) AS pay_cover
FROM tot AS t
JOIN dw.dim_department AS d ON d.department_key = t.dept
LEFT JOIN elig AS e ON e.dept = t.dept
LEFT JOIN cov AS c ON c.dept = t.dept
LEFT JOIN cvr AS v ON v.dept = t.dept
ORDER BY department;
