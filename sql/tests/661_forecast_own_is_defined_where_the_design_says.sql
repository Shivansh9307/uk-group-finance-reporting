-- test: the own forecast exists only for returns R1 to R11 (R0 has no actual month, R12 has no month left), forecasts exactly the months n + 1 to 12, has a seasonal method only where the prior year's R13 exists (never in FY2017-18) and names that year, and every run-rate row equals the year to date divided by n
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
  AND NOT EXISTS (SELECT 1 FROM dw.forecast_own AS o WHERE o.financial_year = h.financial_year AND o.method = 'seasonal');
