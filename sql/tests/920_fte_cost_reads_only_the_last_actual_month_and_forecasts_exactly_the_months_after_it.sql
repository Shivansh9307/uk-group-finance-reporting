-- test: the FTE x cost forecast reads no workforce month after the return's last actual month (no look-ahead): the month it reads is exactly the calendar month of period n of the year, it forecasts exactly the months n + 1 to 12 with one amount, exists only for returns R1 to R11 and never in FY2017-18 (the files start in April 2018), and every coverage row of audit.forecast_fte_cost_coverage has one status: covered exactly where the method has rows, shared_department only where another department group with a pay line answers to the same department in the year (found here from the group code, not from the mapping table)
-- marker: localdata
-- requires: dw.forecast_own_pay, dw.forecast_fte_cost_input, audit.forecast_fte_cost_coverage, dw.forecast_pay_input
SELECT 'workforce month is not the last actual month of the return' AS problem,
       CONCAT(o.financial_year, ' R', o.return_no, ' ', o.department_group_code) AS detail
FROM dw.forecast_own_pay AS o
WHERE o.method = 'fte_cost'
  AND (o.workforce_month IS NULL
       OR o.workforce_month <> DATEADD(MONTH, o.return_no - 1, DATEFROMPARTS(CAST(LEFT(o.financial_year, 4) AS int), 4, 1))
       OR o.input_max_period <> o.return_no)
GROUP BY o.financial_year, o.return_no, o.department_group_code
UNION ALL
SELECT 'a fte_cost row reads a workforce month later than the end of the last actual month',
       CONCAT(o.financial_year, ' R', o.return_no, ' ', o.department_group_code)
FROM dw.forecast_own_pay AS o
WHERE o.method = 'fte_cost'
  AND o.workforce_month > EOMONTH(DATEADD(MONTH, o.return_no - 1, DATEFROMPARTS(CAST(LEFT(o.financial_year, 4) AS int), 4, 1)))
GROUP BY o.financial_year, o.return_no, o.department_group_code
UNION ALL
SELECT 'cell does not forecast exactly the months n + 1 to 12 with one amount',
       CONCAT(financial_year, ' R', return_no, ' ', department_group_code)
FROM dw.forecast_own_pay
WHERE method = 'fte_cost'
GROUP BY financial_year, return_no, department_group_code
HAVING COUNT(*) <> 12 - MIN(return_no) OR MIN(period) <> MIN(return_no) + 1 OR MAX(period) <> 12 OR MIN(amount) <> MAX(amount)
UNION ALL
SELECT 'fte_cost outside R1 to R11 or in FY2017-18', CONCAT(financial_year, ' R', return_no)
FROM dw.forecast_own_pay
WHERE method = 'fte_cost' AND (return_no NOT BETWEEN 1 AND 11 OR financial_year = '2017-18')
GROUP BY financial_year, return_no
UNION ALL
SELECT 'status covered and fte_cost rows do not coincide', CONCAT(c.financial_year, ' R', c.return_no, ' ', c.department_group_code)
FROM audit.forecast_fte_cost_coverage AS c
WHERE CASE WHEN c.status = 'covered' THEN 1 ELSE 0 END <> CASE WHEN EXISTS (SELECT 1 FROM dw.forecast_own_pay AS o
                                                   WHERE o.method = 'fte_cost' AND o.financial_year = c.financial_year
                                                     AND o.return_no = c.return_no AND o.department_group_code = c.department_group_code)
                                     THEN 1 ELSE 0 END
UNION ALL
SELECT 'coverage row missing for a department group with a pay line in a return R1 to R11',
       CONCAT(p.financial_year, ' R', p.return_no, ' ', p.department_group_code)
FROM (SELECT DISTINCT financial_year, return_no, department_group_code FROM dw.forecast_pay_input WHERE return_no BETWEEN 1 AND 11) AS p
WHERE NOT EXISTS (SELECT 1 FROM audit.forecast_fte_cost_coverage AS c
                  WHERE c.financial_year = p.financial_year AND c.return_no = p.return_no AND c.department_group_code = p.department_group_code)
UNION ALL
SELECT 'status is not one of the four', CONCAT(financial_year, ' ', status)
FROM audit.forecast_fte_cost_coverage
WHERE status NOT IN ('covered', 'no_workforce_cell_in_month', 'shared_department', 'no_department')
GROUP BY financial_year, status
UNION ALL
SELECT 'shared_department but no other group of the year has the same department number rule, or the reverse',
       CONCAT(c.financial_year, ' ', c.department_group_code)
FROM audit.forecast_fte_cost_coverage AS c
JOIN dw.department_reported_number AS r ON r.reported_department_number = SUBSTRING(c.department_group_code, 4, 3)
WHERE CASE WHEN c.status = 'shared_department' THEN 1 ELSE 0 END <>
      CASE WHEN EXISTS (SELECT 1
                        FROM (SELECT DISTINCT financial_year, department_group_code FROM dw.forecast_pay_input) AS q
                        JOIN dw.department_reported_number AS r2 ON r2.reported_department_number = SUBSTRING(q.department_group_code, 4, 3)
                        WHERE q.financial_year = c.financial_year AND q.department_group_code <> c.department_group_code
                          AND r2.current_department_key = r.current_department_key) THEN 1 ELSE 0 END
GROUP BY c.financial_year, c.department_group_code, c.status;
