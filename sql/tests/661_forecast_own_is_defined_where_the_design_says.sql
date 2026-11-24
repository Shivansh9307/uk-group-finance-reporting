-- test: the own forecast exists only for returns R1 to R11 (R0 has no actual month, R12 has no month left), forecasts exactly the months n + 1 to 12, has a seasonal method only where the prior year's R13 exists (never in FY2017-18) and names that year, every run-rate row equals the year to date divided by n, and the seasonal forecast exists exactly where the guard holds: the prior year's months 1 to n have the same sign as the year to date and are at least a tenth of the prior year's full total
-- requires: dw.forecast_own, dw.forecast_return_header
SELECT 'own forecast for a return outside R1 to R11' AS problem, financial_year + ' R' + CAST(return_no AS varchar(10)) AS detail
FROM dw.forecast_own WHERE return_no NOT BETWEEN 1 AND 11 GROUP BY financial_year, return_no
UNION ALL
SELECT 'cell does not forecast exactly the months n + 1 to 12',
       financial_year + ' R' + CAST(return_no AS varchar(10)) + ' ' + department_group_code + ' ' + budget_measure + ' ' + method
FROM dw.forecast_own
GROUP BY financial_year, return_no, department_group_code, budget_measure, method
HAVING COUNT(*) <> 12 - return_no OR MIN(period) <> return_no + 1 OR MAX(period) <> 12
UNION ALL
SELECT 'seasonal forecast without a prior year, or a wrong prior year', o.financial_year + ' R' + CAST(o.return_no AS varchar(10))
FROM dw.forecast_own AS o
LEFT JOIN dw.forecast_return_header AS c ON c.financial_year = o.financial_year AND c.return_no = 13
LEFT JOIN dw.forecast_return_header AS p ON p.year_seq = c.year_seq - 1 AND p.return_no = 13
WHERE o.method = 'seasonal' AND (p.financial_year IS NULL OR o.profile_financial_year <> p.financial_year OR o.profile_ytd_amount IS NULL OR o.profile_ytd_amount = 0)
GROUP BY o.financial_year, o.return_no
UNION ALL
SELECT 'run rate row carries a profile or does not equal ytd / n', o.financial_year + ' R' + CAST(o.return_no AS varchar(10))
FROM dw.forecast_own AS o
WHERE o.method = 'run_rate'
  AND (o.profile_financial_year IS NOT NULL
       OR o.amount <> CAST(CAST(o.ytd_amount AS decimal(20, 6)) / CAST(o.return_no AS decimal(10, 0)) AS decimal(19, 4)))
GROUP BY o.financial_year, o.return_no
UNION ALL
SELECT 'FY2017-18 has a seasonal forecast', 'FY2017-18' FROM dw.forecast_own WHERE financial_year = '2017-18' AND method = 'seasonal' GROUP BY method
UNION ALL
SELECT 'a year with a prior year has no seasonal forecast at all', h.financial_year
FROM dw.forecast_return_header AS h
WHERE h.return_no = 13 AND h.year_seq > 1
  AND NOT EXISTS (SELECT 1 FROM dw.forecast_own AS o WHERE o.financial_year = h.financial_year AND o.method = 'seasonal')

UNION ALL
SELECT 'seasonal row breaks the guard (same sign as the year to date, profile months 1 to n at least a tenth of the prior year)',
       o.financial_year + ' R' + CAST(o.return_no AS varchar(10)) + ' ' + o.department_group_code + ' ' + o.budget_measure
FROM dw.forecast_own AS o
WHERE o.method = 'seasonal'
  AND NOT (o.ytd_amount > 0 AND o.profile_ytd_amount > 0 OR o.ytd_amount < 0 AND o.profile_ytd_amount < 0)
   OR o.method = 'seasonal' AND ABS(o.profile_ytd_amount) * 10 < ABS(o.profile_year_amount)
GROUP BY o.financial_year, o.return_no, o.department_group_code, o.budget_measure
UNION ALL
SELECT 'cell that passes the guard has no seasonal forecast, or a cell that fails it has one',
       r.financial_year + ' R' + CAST(r.return_no AS varchar(10)) + ' ' + r.department_group_code + ' ' + r.budget_measure
FROM (SELECT DISTINCT financial_year, return_no, department_group_code, budget_measure, ytd_amount FROM dw.forecast_own WHERE method = 'run_rate') AS r
LEFT JOIN dw.forecast_prior_profile AS pp
       ON pp.financial_year = r.financial_year AND pp.department_group_code = r.department_group_code AND pp.budget_measure = r.budget_measure
GROUP BY r.financial_year, r.return_no, r.department_group_code, r.budget_measure, r.ytd_amount
HAVING CASE WHEN COUNT(pp.period) > 0
             AND ABS(SUM(CASE WHEN pp.period <= r.return_no THEN pp.amount ELSE 0 END)) * 10 >= ABS(SUM(pp.amount))
             AND (r.ytd_amount > 0 AND SUM(CASE WHEN pp.period <= r.return_no THEN pp.amount ELSE 0 END) > 0
               OR r.ytd_amount < 0 AND SUM(CASE WHEN pp.period <= r.return_no THEN pp.amount ELSE 0 END) < 0) THEN 1 ELSE 0 END
       <> CASE WHEN EXISTS (SELECT 1 FROM dw.forecast_own AS s WHERE s.method = 'seasonal' AND s.financial_year = r.financial_year
                              AND s.return_no = r.return_no AND s.department_group_code = r.department_group_code
                              AND s.budget_measure = r.budget_measure) THEN 1 ELSE 0 END;
