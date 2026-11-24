-- test: the accuracy the model reads has rows for every method (the department and my run rate and seasonal methods on the budget measure totals; those three and FTE x cost on the pay line), every department group maps to a department of the current structure, the two named flagged returns are present and flagged (FCDO R0 of FY2020-21, Department of Health R1 of FY2018-19), the "without" version drops exactly the rows of the flagged department-group returns of dw.forecast_return_quality and no others, and each of the two named cells ties the difference: the department's absolute error in its year is larger with the cell than without it, and the year without all flagged returns is lower than the year with them by at least that cell's error, so the with and without versions cannot be the same figure
-- requires: dw.v_model_forecast_accuracy, dw.forecast_return_quality, dw.forecast_group_department, dw.forecast_accuracy, dw.forecast_pay_accuracy
SELECT 'a method has no accuracy row on its line' AS problem, CONCAT(e.forecast_line, ' ', e.method) AS detail
FROM (VALUES ('Total', 'department'), ('Total', 'run_rate'), ('Total', 'seasonal'),
             ('Pay', 'department'), ('Pay', 'run_rate'), ('Pay', 'seasonal'), ('Pay', 'fte_cost')) AS e (forecast_line, method)
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_forecast_accuracy AS a WHERE a.forecast_line = e.forecast_line AND a.method = e.method)
UNION ALL
SELECT 'FTE x cost on the budget measure total, or a method that is not one of the four', CONCAT(forecast_line, ' ', method)
FROM dw.v_model_forecast_accuracy
WHERE (forecast_line = 'Total' AND method = 'fte_cost') OR method NOT IN ('department', 'run_rate', 'seasonal', 'fte_cost')
GROUP BY forecast_line, method
UNION ALL
SELECT 'department group with no department of the current structure', g.department_group_code
FROM dw.forecast_group_department AS g
WHERE g.department_group_code IN (SELECT department_group_code FROM dw.forecast_accuracy UNION SELECT department_group_code FROM dw.forecast_pay_accuracy)
  AND g.department_key = -1
UNION ALL
SELECT 'a flagged return is missing or not flagged', c.what
FROM (VALUES ('FCDO R0 FY2020-21', '2020-21', 0, 'DID030.GROUP'), ('Department of Health R1 FY2018-19', '2018-19', 1, 'DOH033.GROUP')) AS c (what, fy, r, grp)
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_forecast_accuracy AS a
                  WHERE a.forecast_line = 'Total' AND a.method = 'department' AND a.financial_year = c.fy AND a.return_no = c.r
                    AND a.department_group_code = c.grp AND a.flagged_return = 1)
UNION ALL
SELECT 'a row is flagged but its group-return is not in the quality table', CONCAT(a.financial_year, ' R', a.return_no, ' ', a.department_group_code)
FROM dw.v_model_forecast_accuracy AS a
WHERE a.flagged_return = 1
  AND NOT EXISTS (SELECT 1 FROM dw.forecast_return_quality AS q
                  WHERE q.financial_year = a.financial_year AND q.return_no = a.return_no AND q.department_group_code = a.department_group_code)
GROUP BY a.financial_year, a.return_no, a.department_group_code
UNION ALL
SELECT 'a row of a flagged group-return is not flagged', CONCAT(a.financial_year, ' R', a.return_no, ' ', a.department_group_code)
FROM dw.v_model_forecast_accuracy AS a
WHERE a.flagged_return = 0
  AND EXISTS (SELECT 1 FROM dw.forecast_return_quality AS q
              WHERE q.financial_year = a.financial_year AND q.return_no = a.return_no AND q.department_group_code = a.department_group_code)
GROUP BY a.financial_year, a.return_no, a.department_group_code
UNION ALL
SELECT 'the without version does not drop exactly the flagged rows', 'row count'
FROM (SELECT (SELECT COUNT(*) FROM dw.v_model_forecast_accuracy WHERE flagged_return = 0) AS without_n,
             (SELECT COUNT(*) FROM dw.v_model_forecast_accuracy) AS all_n,
             (SELECT COUNT(*) FROM dw.v_model_forecast_accuracy AS a
              WHERE EXISTS (SELECT 1 FROM dw.forecast_return_quality AS q
                            WHERE q.financial_year = a.financial_year AND q.return_no = a.return_no
                              AND q.department_group_code = a.department_group_code)) AS flagged_n) AS t
WHERE t.without_n <> t.all_n - t.flagged_n
UNION ALL
SELECT 'the named cell has no absolute error, or the year without the flagged returns is not lower than the year with them by at least that cell''s error', t.what
FROM (
    SELECT c.what,
           SUM(a.full_year_abs_error) AS year_all,
           SUM(CASE WHEN a.flagged_return = 0 THEN a.full_year_abs_error ELSE 0 END) AS year_unflagged,
           SUM(CASE WHEN a.return_no = c.r AND a.department_group_code = c.grp THEN a.full_year_abs_error ELSE 0 END) AS cell_error,
           SUM(CASE WHEN NOT (a.return_no = c.r AND a.department_group_code = c.grp) THEN a.full_year_abs_error ELSE 0 END) AS year_without_cell
    FROM (VALUES ('FCDO R0 FY2020-21', '2020-21', 0, 'DID030.GROUP'), ('Department of Health R1 FY2018-19', '2018-19', 1, 'DOH033.GROUP')) AS c (what, fy, r, grp)
    JOIN dw.v_model_forecast_accuracy AS a ON a.financial_year = c.fy
    WHERE a.forecast_line = 'Total' AND a.method = 'department'
    GROUP BY c.what, c.fy, c.r, c.grp
) AS t
WHERE t.cell_error <= 0                          -- the named cell has an error to remove
   OR t.year_without_cell >= t.year_all          -- removing that cell alone lowers the year's error
   OR t.year_all - t.year_unflagged < t.cell_error;   -- dropping all flagged returns removes at least that cell's error
