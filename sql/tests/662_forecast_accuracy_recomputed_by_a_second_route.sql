-- test: the accuracy table recomputed by a second route, straight from dw.forecast_return (the department's forecast and my run rate, for every department group, budget measure, year and return), gives exactly the same full-year forecast and outturn, forecast-month error, absolute error and absolute outturn, and so the same WAPE and bias; every ratio, full-year and forecast-month, is the ratio of its sums, and MAPE exists only for a full-year outturn of at least GBP 100m
-- requires: dw.forecast_accuracy, dw.forecast_return, dw.forecast_return_header
WITH months AS (
    SELECT m.period FROM (VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12)) AS m (period)
),
cell AS (
    SELECT r.financial_year, r.return_no, r.department_group_code, r.budget_measure, r.period, SUM(r.amount) AS amount
    FROM dw.forecast_return AS r
    WHERE r.period BETWEEN 1 AND 12 AND r.budget_measure IN ('RDEL', 'CDEL', 'AME')
    GROUP BY r.financial_year, r.return_no, r.department_group_code, r.budget_measure, r.period
),
dept AS (
    -- route B for the department: pair every month of return n with the same month of R13, cell by cell
    SELECT k.financial_year, k.return_no, k.department_group_code, k.budget_measure, 'department' AS method,
           SUM(COALESCE(a.amount, 0)) AS full_year_forecast, SUM(COALESCE(f.amount, 0)) AS full_year_outturn,
           SUM(CASE WHEN mo.period > k.return_no THEN COALESCE(a.amount, 0) - COALESCE(f.amount, 0) ELSE 0 END) AS fm_error,
           SUM(CASE WHEN mo.period > k.return_no THEN ABS(COALESCE(a.amount, 0) - COALESCE(f.amount, 0)) ELSE 0 END) AS fm_abs_error,
           SUM(CASE WHEN mo.period > k.return_no THEN ABS(COALESCE(f.amount, 0)) ELSE 0 END) AS fm_abs_outturn
    FROM (SELECT DISTINCT financial_year, return_no, department_group_code, budget_measure FROM cell WHERE return_no <= 12
          UNION
          SELECT DISTINCT h.financial_year, h.return_no, c.department_group_code, c.budget_measure
          FROM cell AS c JOIN dw.forecast_return_header AS h ON h.financial_year = c.financial_year AND h.return_no <= 12
          WHERE c.return_no = 13) AS k
    CROSS JOIN months AS mo
    LEFT JOIN cell AS a ON a.financial_year = k.financial_year AND a.return_no = k.return_no AND a.department_group_code = k.department_group_code
                       AND a.budget_measure = k.budget_measure AND a.period = mo.period
    LEFT JOIN cell AS f ON f.financial_year = k.financial_year AND f.return_no = 13 AND f.department_group_code = k.department_group_code
                       AND f.budget_measure = k.budget_measure AND f.period = mo.period
    GROUP BY k.financial_year, k.return_no, k.department_group_code, k.budget_measure
),
rr AS (
    -- route B for the run rate: actual months of return n, the mean of them for the rest
    SELECT k.financial_year, k.return_no, k.department_group_code, k.budget_measure, 'run_rate' AS method,
           SUM(CASE WHEN mo.period <= k.return_no THEN COALESCE(a.amount, 0) ELSE k.rate END) AS full_year_forecast,
           SUM(COALESCE(f.amount, 0)) AS full_year_outturn,
           SUM(CASE WHEN mo.period > k.return_no THEN k.rate - COALESCE(f.amount, 0) ELSE 0 END) AS fm_error,
           SUM(CASE WHEN mo.period > k.return_no THEN ABS(k.rate - COALESCE(f.amount, 0)) ELSE 0 END) AS fm_abs_error,
           SUM(CASE WHEN mo.period > k.return_no THEN ABS(COALESCE(f.amount, 0)) ELSE 0 END) AS fm_abs_outturn
    FROM (SELECT c.financial_year, c.return_no, c.department_group_code, c.budget_measure,
                 CAST(CAST(SUM(c.amount) AS decimal(20, 6)) / CAST(c.return_no AS decimal(10, 0)) AS decimal(19, 4)) AS rate
          FROM cell AS c WHERE c.return_no BETWEEN 1 AND 11 AND c.period <= c.return_no
          GROUP BY c.financial_year, c.return_no, c.department_group_code, c.budget_measure) AS k
    CROSS JOIN months AS mo
    LEFT JOIN cell AS a ON a.financial_year = k.financial_year AND a.return_no = k.return_no AND a.department_group_code = k.department_group_code
                       AND a.budget_measure = k.budget_measure AND a.period = mo.period AND mo.period <= k.return_no
    LEFT JOIN cell AS f ON f.financial_year = k.financial_year AND f.return_no = 13 AND f.department_group_code = k.department_group_code
                       AND f.budget_measure = k.budget_measure AND f.period = mo.period
    GROUP BY k.financial_year, k.return_no, k.department_group_code, k.budget_measure
),
routeb AS (SELECT * FROM dept UNION ALL SELECT * FROM rr)
SELECT 'accuracy differs from the second route' AS problem,
       COALESCE(b.financial_year, a.financial_year) + ' R' + CAST(COALESCE(b.return_no, a.return_no) AS varchar(10)) + ' '
         + COALESCE(b.department_group_code, a.department_group_code) + ' ' + COALESCE(b.budget_measure, a.budget_measure) + ' '
         + COALESCE(b.method, a.method) AS detail
FROM routeb AS b
FULL OUTER JOIN dw.forecast_accuracy AS a
  ON a.financial_year = b.financial_year AND a.return_no = b.return_no AND a.department_group_code = b.department_group_code
 AND a.budget_measure = b.budget_measure AND a.method = b.method
WHERE a.method IN ('department', 'run_rate') AND b.method IS NULL
   OR b.method IS NOT NULL AND (a.method IS NULL OR a.full_year_forecast <> b.full_year_forecast OR a.full_year_outturn <> b.full_year_outturn
        OR a.fm_error <> b.fm_error OR a.fm_abs_error <> b.fm_abs_error OR a.fm_abs_outturn <> b.fm_abs_outturn)
UNION ALL
SELECT 'ratio is not the ratio of its sums', financial_year + ' R' + CAST(return_no AS varchar(10)) + ' ' + department_group_code + ' ' + budget_measure + ' ' + method
FROM dw.forecast_accuracy
WHERE (fm_abs_outturn = 0 AND (fm_wape IS NOT NULL OR fm_bias IS NOT NULL))
   OR (fm_abs_outturn <> 0 AND (fm_wape IS NULL OR fm_bias IS NULL
        OR ABS(fm_wape * fm_abs_outturn - fm_abs_error) > 0.001 + 0.0000000001 * fm_abs_outturn
        OR ABS(fm_bias * fm_abs_outturn - fm_error) > 0.001 + 0.0000000001 * fm_abs_outturn))
   OR (full_year_abs_outturn = 0 AND (wape IS NOT NULL OR bias IS NOT NULL))
   OR (full_year_abs_outturn <> 0 AND (wape IS NULL OR bias IS NULL
        OR ABS(wape * full_year_abs_outturn - full_year_abs_error) > 0.001 + 0.0000000001 * full_year_abs_outturn
        OR ABS(bias * full_year_abs_outturn - full_year_error) > 0.001 + 0.0000000001 * full_year_abs_outturn))
   OR full_year_abs_error <> ABS(full_year_error) OR full_year_abs_outturn <> ABS(full_year_outturn)
   OR full_year_error <> full_year_forecast - full_year_outturn
   OR (full_year_outturn < 100000 AND mape IS NOT NULL) OR (full_year_outturn >= 100000 AND mape IS NULL);
