-- requires: dw.forecast_accuracy, dw.forecast_pay_accuracy
-- Independent of the model views: read from the accuracy tables of dw, with the line, the method name and the number of methods a
-- cell was scored by worked out here (a cell is a department group, budget measure, financial year and return of one line).
-- The model's ratios agree with this query to within 0.000001 (the largest difference on these tests in evidence/model/dax_tests.csv is 0.00000099; the comparison tolerance is 0.0001): the SQL carries 10 decimal places, the agreement is to 6.
WITH acc AS (
    SELECT 'Total' AS line, a.* FROM dw.forecast_accuracy AS a
    UNION ALL
    SELECT 'Pay', a.* FROM dw.forecast_pay_accuracy AS a
),
x AS (
    SELECT acc.*,
           CASE acc.method WHEN 'department' THEN N'Department' WHEN 'run_rate' THEN N'Run rate' WHEN 'seasonal' THEN N'Seasonal'
                           ELSE N'FTE x cost' END AS method_name,
           COUNT(*) OVER (PARTITION BY acc.line, acc.financial_year, acc.return_no, acc.department_group_code, acc.budget_measure) AS n_methods
    FROM acc
)

SELECT x.department_group_code, x.financial_year, CONCAT('R', x.return_no) AS return_label, x.budget_measure,
       COUNT_BIG(*) AS flagged_cells,
       CAST(0 AS bigint) AS cells_excl,
       CAST(SUM(x.full_year_abs_error) AS decimal(38, 4)) AS abs_error,
       CAST(SUM(x.full_year_abs_outturn) AS decimal(38, 4)) AS abs_outturn,
       CAST(SUM(CAST(x.full_year_abs_error AS decimal(38, 10))) / NULLIF(SUM(CAST(x.full_year_abs_outturn AS decimal(38, 10))), 0) AS decimal(38, 10)) AS wape
FROM x
WHERE x.line = 'Total' AND x.method = 'department' AND x.is_flagged_return = 1
  AND ((x.department_group_code = 'DID030.GROUP' AND x.financial_year = '2020-21' AND x.return_no = 0)
    OR (x.department_group_code = 'DOH033.GROUP' AND x.financial_year = '2018-19' AND x.return_no = 1))
GROUP BY x.department_group_code, x.financial_year, x.return_no, x.budget_measure
ORDER BY department_group_code, financial_year, return_label, budget_measure;
