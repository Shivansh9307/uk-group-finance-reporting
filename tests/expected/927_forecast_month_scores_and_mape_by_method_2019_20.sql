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

SELECT x.method_name AS method,
       CAST(SUM(CAST(x.fm_abs_error AS decimal(38, 10))) / SUM(CAST(x.fm_abs_outturn AS decimal(38, 10))) AS decimal(38, 10)) AS fm_wape,
       CAST(SUM(CASE WHEN x.is_flagged_return = 0 THEN CAST(x.fm_abs_error AS decimal(38, 10)) END)
            / SUM(CASE WHEN x.is_flagged_return = 0 THEN CAST(x.fm_abs_outturn AS decimal(38, 10)) END) AS decimal(38, 10)) AS fm_wape_excl,
       CAST(SUM(CAST(x.fm_error AS decimal(38, 10))) / SUM(CAST(x.fm_abs_outturn AS decimal(38, 10))) AS decimal(38, 10)) AS fm_bias,
       CAST(SUM(CASE WHEN x.is_flagged_return = 0 THEN CAST(x.fm_error AS decimal(38, 10)) END)
            / SUM(CASE WHEN x.is_flagged_return = 0 THEN CAST(x.fm_abs_outturn AS decimal(38, 10)) END) AS decimal(38, 10)) AS fm_bias_excl,
       CAST(SUM(CASE WHEN x.mape IS NOT NULL THEN CAST(x.full_year_abs_error AS decimal(38, 10)) END)
            / SUM(CASE WHEN x.mape IS NOT NULL THEN CAST(x.full_year_outturn AS decimal(38, 10)) END) AS decimal(38, 10)) AS mape,
       CAST(SUM(CASE WHEN x.mape IS NOT NULL AND x.is_flagged_return = 0 THEN CAST(x.full_year_abs_error AS decimal(38, 10)) END)
            / SUM(CASE WHEN x.mape IS NOT NULL AND x.is_flagged_return = 0 THEN CAST(x.full_year_outturn AS decimal(38, 10)) END) AS decimal(38, 10)) AS mape_excl
FROM x
WHERE x.line = 'Total' AND x.n_methods = 3 AND x.financial_year = '2019-20'
GROUP BY x.method_name
ORDER BY method;
