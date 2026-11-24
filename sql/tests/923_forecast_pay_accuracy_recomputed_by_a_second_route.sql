-- test: the pay-line accuracy (dw.forecast_pay_accuracy) is recomputed by a second route, straight from dw.forecast_return with a different query shape (no month table): for the department, the full-year forecast is the pay line of return n over months 1 to 12 and the outturn is the pay line of R13; for the run rate it is the year to date times 12 / n; for FTE x cost it is the year to date plus (12 - n) times the paybill of the last actual month divided by 1,000, the paybill taken from dw.workforce_month; each full-year error and absolute error is rebuilt from those (to within 0.001: the build rounds each forecast month to four places) and the ratio WAPE is the ratio of the table's own sums, and every cell and method of each side is on the other side. Pay amounts are GBP thousands, workforce paybill is pounds
-- marker: localdata
-- requires: dw.forecast_pay_accuracy, dw.forecast_return, dw.forecast_own_pay
WITH pay AS (
    SELECT financial_year, return_no, department_group_code,
           SUM(CASE WHEN period BETWEEN 1 AND 12 THEN amount ELSE 0 END) AS year_total,
           SUM(CASE WHEN period BETWEEN 1 AND return_no THEN amount ELSE 0 END) AS ytd
    FROM dw.forecast_return
    WHERE budget_measure = 'RDEL' AND economic_category_code = 'A101' AND return_no BETWEEN 0 AND 13 AND period BETWEEN 1 AND 12
    GROUP BY financial_year, return_no, department_group_code
),
fin AS (SELECT financial_year, department_group_code, year_total AS outturn FROM pay WHERE return_no = 13),
cells AS (
    SELECT financial_year, return_no, department_group_code FROM pay WHERE return_no BETWEEN 0 AND 12
    UNION
    SELECT h.financial_year, h.return_no, f.department_group_code
    FROM fin AS f JOIN dw.forecast_return_header AS h ON h.financial_year = f.financial_year AND h.return_no BETWEEN 0 AND 12
),
dept AS (
    SELECT c.financial_year, c.return_no, c.department_group_code, 'department' AS method,
           COALESCE(p.year_total, 0) AS fcst, COALESCE(f.outturn, 0) AS outturn
    FROM cells AS c
    LEFT JOIN pay AS p ON p.financial_year = c.financial_year AND p.return_no = c.return_no AND p.department_group_code = c.department_group_code
    LEFT JOIN fin AS f ON f.financial_year = c.financial_year AND f.department_group_code = c.department_group_code
),
rr AS (
    SELECT p.financial_year, p.return_no, p.department_group_code, 'run_rate' AS method,
           CAST(p.ytd AS decimal(20, 6)) * 12 / p.return_no AS fcst, COALESCE(f.outturn, 0) AS outturn
    FROM pay AS p LEFT JOIN fin AS f ON f.financial_year = p.financial_year AND f.department_group_code = p.department_group_code
    WHERE p.return_no BETWEEN 1 AND 11 AND EXISTS (SELECT 1 FROM dw.forecast_own_pay AS o
                                                   WHERE o.method = 'run_rate' AND o.financial_year = p.financial_year
                                                     AND o.return_no = p.return_no AND o.department_group_code = p.department_group_code)
),
ftc AS (
    SELECT p.financial_year, p.return_no, p.department_group_code, 'fte_cost' AS method,
           p.ytd + (12 - p.return_no) * CAST(o.workforce_paybill_gbp AS decimal(24, 6)) / 1000 AS fcst, COALESCE(f.outturn, 0) AS outturn
    FROM pay AS p
    JOIN (SELECT DISTINCT financial_year, return_no, department_group_code, workforce_paybill_gbp
          FROM dw.forecast_own_pay WHERE method = 'fte_cost') AS o
      ON o.financial_year = p.financial_year AND o.return_no = p.return_no AND o.department_group_code = p.department_group_code
    LEFT JOIN fin AS f ON f.financial_year = p.financial_year AND f.department_group_code = p.department_group_code
    WHERE p.return_no BETWEEN 1 AND 11
),
pri AS (   -- the prior year's R13 pay line by month, attached to the year it profiles
    SELECT cur.financial_year, r.department_group_code, r.period, SUM(r.amount) AS amount
    FROM dw.forecast_return_header AS cur
    JOIN dw.forecast_return_header AS prv ON prv.year_seq = cur.year_seq - 1 AND prv.return_no = 13
    JOIN dw.forecast_return AS r ON r.financial_year = prv.financial_year AND r.return_no = 13 AND r.period BETWEEN 1 AND 12
                                AND r.budget_measure = 'RDEL' AND r.economic_category_code = 'A101'
    WHERE cur.return_no = 13
    GROUP BY cur.financial_year, r.department_group_code, r.period
),
sb AS (
    SELECT p.financial_year, p.return_no, p.department_group_code, p.ytd, SUM(q.amount) AS year_total,
           SUM(CASE WHEN q.period <= p.return_no THEN q.amount ELSE 0 END) AS ytd_n
    FROM pay AS p
    JOIN pri AS q ON q.financial_year = p.financial_year AND q.department_group_code = p.department_group_code
    WHERE p.return_no BETWEEN 1 AND 11
    GROUP BY p.financial_year, p.return_no, p.department_group_code, p.ytd
),
sea AS (   -- seasonal: the year to date times the prior year's twelve months over its months 1 to n, under the guard
    SELECT b.financial_year, b.return_no, b.department_group_code, 'seasonal' AS method,
           CAST(b.ytd AS decimal(20, 6)) * b.year_total / b.ytd_n AS fcst, COALESCE(f.outturn, 0) AS outturn
    FROM sb AS b
    LEFT JOIN fin AS f ON f.financial_year = b.financial_year AND f.department_group_code = b.department_group_code
    WHERE b.ytd <> 0 AND b.ytd_n <> 0 AND SIGN(b.ytd_n) = SIGN(b.ytd) AND ABS(b.ytd_n) >= 0.1 * ABS(b.year_total)
),
expd AS (
    SELECT * FROM dept UNION ALL SELECT * FROM rr UNION ALL SELECT * FROM sea UNION ALL SELECT * FROM ftc
)
SELECT 'cell on one side only' AS problem, CONCAT(COALESCE(e.financial_year, a.financial_year), ' R', COALESCE(e.return_no, a.return_no), ' ',
       COALESCE(e.department_group_code, a.department_group_code), ' ', COALESCE(e.method, a.method)) AS detail
FROM expd AS e
FULL JOIN dw.forecast_pay_accuracy AS a
       ON a.financial_year = e.financial_year AND a.return_no = e.return_no AND a.department_group_code = e.department_group_code
      AND a.method = e.method
WHERE e.financial_year IS NULL OR a.financial_year IS NULL
UNION ALL
SELECT 'full-year forecast, outturn or error differs', CONCAT(a.financial_year, ' R', a.return_no, ' ', a.department_group_code, ' ', a.method)
FROM expd AS e
JOIN dw.forecast_pay_accuracy AS a
  ON a.financial_year = e.financial_year AND a.return_no = e.return_no AND a.department_group_code = e.department_group_code
 AND a.method = e.method
WHERE ABS(a.full_year_forecast - e.fcst) > 0.001 OR ABS(a.full_year_outturn - e.outturn) > 0.0001
   OR ABS(a.full_year_error - (e.fcst - e.outturn)) > 0.001 OR ABS(a.full_year_abs_error - ABS(e.fcst - e.outturn)) > 0.001
   OR CASE WHEN e.outturn <> 0 THEN ABS(a.wape - CAST(a.full_year_abs_error AS decimal(30, 10)) / ABS(e.outturn)) END > 0.000000001;
