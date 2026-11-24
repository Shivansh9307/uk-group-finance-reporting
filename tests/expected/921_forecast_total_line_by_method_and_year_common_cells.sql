-- requires: dw.forecast_accuracy, dw.forecast_pay_accuracy
-- Independent of the model views: read from the accuracy tables of dw, with the line, the method name and the number of methods a
-- cell was scored by worked out here (a cell is a department group, budget measure, financial year and return of one line).
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

SELECT x.method_name AS method, x.financial_year,
       COUNT_BIG(*) AS cells,
       SUM(CASE WHEN x.is_flagged_return = 0 THEN 1 ELSE 0 END) AS cells_excl,
       CAST(SUM(x.full_year_abs_error) AS decimal(38, 4)) AS abs_error,
       CAST(SUM(CASE WHEN x.is_flagged_return = 0 THEN x.full_year_abs_error END) AS decimal(38, 4)) AS abs_error_excl,
       CAST(SUM(CAST(x.full_year_abs_error AS decimal(38, 10))) / SUM(CAST(x.full_year_abs_outturn AS decimal(38, 10))) AS decimal(38, 10)) AS wape,
       CAST(SUM(CASE WHEN x.is_flagged_return = 0 THEN CAST(x.full_year_abs_error AS decimal(38, 10)) END)
            / SUM(CASE WHEN x.is_flagged_return = 0 THEN CAST(x.full_year_abs_outturn AS decimal(38, 10)) END) AS decimal(38, 10)) AS wape_excl,
       CAST(SUM(CAST(x.full_year_error AS decimal(38, 10))) / SUM(CAST(x.full_year_abs_outturn AS decimal(38, 10))) AS decimal(38, 10)) AS bias,
       CAST(SUM(CASE WHEN x.is_flagged_return = 0 THEN CAST(x.full_year_error AS decimal(38, 10)) END)
            / SUM(CASE WHEN x.is_flagged_return = 0 THEN CAST(x.full_year_abs_outturn AS decimal(38, 10)) END) AS decimal(38, 10)) AS bias_excl
FROM x
WHERE x.line = 'Total' AND x.n_methods = 3
GROUP BY x.method_name, x.financial_year
ORDER BY method, financial_year;
