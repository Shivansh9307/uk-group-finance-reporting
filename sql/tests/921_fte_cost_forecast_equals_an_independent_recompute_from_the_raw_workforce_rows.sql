-- test: the FTE x cost forecast of every covered department group, year and return equals a second computation from the raw rows of dw.workforce_month: the valid cells are found again here (published full-time equivalent and paybill both above zero, and not on the list of cells left out of the pay bridge), the department of a cell is the version in force found by a window function, the paybill is added first and divided by 1,000 last (the build multiplies the full-time equivalent by the average cost per full-time equivalent), the set of cells is the same both ways, and the lineage columns (full-time equivalent, paybill, cost per full-time equivalent) agree with the raw sums. This can fail: a wrong month, a wrong department, an excluded cell counted, or a unit slip
-- marker: localdata
-- requires: dw.forecast_own_pay, dw.workforce_month, audit.pay_excluded_cell, dw.forecast_group_department
WITH f AS (
    SELECT w.durable_key, w.month_start, w.report_month,
           MAX(CASE WHEN w.measure_key = 'payroll_fte' THEN w.value END) AS fte,
           MAX(CASE WHEN w.measure_key = 'payroll_paybill_gbp' THEN w.value END) AS paybill
    FROM dw.workforce_month AS w
    WHERE w.measure_key IN ('payroll_fte', 'payroll_paybill_gbp')
    GROUP BY w.durable_key, w.month_start, w.report_month
),
v AS (   -- the cells that are valid: both numbers above zero and not on the excluded list
    SELECT f.* FROM f
    WHERE f.fte > 0 AND f.paybill > 0
      AND NOT EXISTS (SELECT 1 FROM audit.pay_excluded_cell AS x WHERE x.durable_key = f.durable_key AND x.month_start = f.month_start)
),
ver AS (   -- organisation versions with the release each one starts in, ranked within a durable key
    SELECT o.durable_key, o.valid_from_release, d.department_number,
           ROW_NUMBER() OVER (PARTITION BY o.durable_key ORDER BY o.valid_from_release) AS first_rank
    FROM dw.dim_organisation AS o
    JOIN dw.dim_department AS d ON d.department_key = o.department_key
),
cell AS (
    SELECT v.durable_key, v.month_start, v.fte, v.paybill,
           COALESCE(
               (SELECT TOP (1) x.department_number FROM ver AS x
                WHERE x.durable_key = v.durable_key AND x.valid_from_release <= v.report_month
                ORDER BY x.valid_from_release DESC),
               (SELECT x.department_number FROM ver AS x WHERE x.durable_key = v.durable_key AND x.first_rank = 1)) AS department_number
    FROM v
),
dept AS (
    SELECT r.current_department_key AS department_key, c.month_start, SUM(c.paybill) AS paybill, SUM(c.fte) AS fte
    FROM cell AS c
    JOIN dw.department_reported_number AS r ON r.reported_department_number = c.department_number
    GROUP BY r.current_department_key, c.month_start
),
expd AS (
    SELECT p.financial_year, p.return_no, p.department_group_code, d.paybill, d.fte
    FROM (SELECT DISTINCT financial_year, return_no, department_group_code FROM dw.forecast_pay_input WHERE return_no BETWEEN 1 AND 11) AS p
    JOIN dw.department_reported_number AS r ON r.reported_department_number = SUBSTRING(p.department_group_code, 4, 3)
    JOIN dept AS d ON d.department_key = r.current_department_key
                  AND d.month_start = DATEADD(MONTH, p.return_no - 1, DATEFROMPARTS(CAST(LEFT(p.financial_year, 4) AS int), 4, 1))
    WHERE NOT EXISTS (SELECT 1
                      FROM (SELECT DISTINCT financial_year, department_group_code FROM dw.forecast_pay_input) AS q
                      JOIN dw.department_reported_number AS r2 ON r2.reported_department_number = SUBSTRING(q.department_group_code, 4, 3)
                      WHERE q.financial_year = p.financial_year AND q.department_group_code <> p.department_group_code
                        AND r2.current_department_key = r.current_department_key)
),
got AS (
    SELECT financial_year, return_no, department_group_code, MIN(amount) AS amount, MIN(workforce_fte) AS fte,
           MIN(workforce_paybill_gbp) AS paybill, MIN(cost_per_fte_gbp) AS cost
    FROM dw.forecast_own_pay WHERE method = 'fte_cost'
    GROUP BY financial_year, return_no, department_group_code
)
SELECT 'fte_cost row with no recomputed cell' AS problem, CONCAT(g.financial_year, ' R', g.return_no, ' ', g.department_group_code) AS detail
FROM got AS g
WHERE NOT EXISTS (SELECT 1 FROM expd AS e WHERE e.financial_year = g.financial_year AND e.return_no = g.return_no AND e.department_group_code = g.department_group_code)
UNION ALL
SELECT 'recomputed cell with no fte_cost row', CONCAT(e.financial_year, ' R', e.return_no, ' ', e.department_group_code)
FROM expd AS e
WHERE NOT EXISTS (SELECT 1 FROM got AS g WHERE e.financial_year = g.financial_year AND e.return_no = g.return_no AND e.department_group_code = g.department_group_code)
UNION ALL
SELECT 'forecast differs from the paybill of the month divided by 1,000', CONCAT(g.financial_year, ' R', g.return_no, ' ', g.department_group_code)
FROM got AS g
JOIN expd AS e ON e.financial_year = g.financial_year AND e.return_no = g.return_no AND e.department_group_code = g.department_group_code
WHERE ABS(g.amount - CAST(e.paybill / 1000 AS decimal(19, 4))) > 0.0001
UNION ALL
SELECT 'lineage differs from the raw sums', CONCAT(g.financial_year, ' R', g.return_no, ' ', g.department_group_code)
FROM got AS g
JOIN expd AS e ON e.financial_year = g.financial_year AND e.return_no = g.return_no AND e.department_group_code = g.department_group_code
WHERE g.fte <> e.fte OR g.paybill <> e.paybill
   OR ABS(g.cost - CAST(e.paybill AS decimal(22, 4)) / CAST(e.fte AS decimal(15, 4))) > 0.000001
UNION ALL
SELECT 'fte_cost row for fewer cells than the covered rows of the coverage audit', 'count'
FROM (SELECT (SELECT COUNT(*) FROM got) AS a, (SELECT COUNT(*) FROM audit.forecast_fte_cost_coverage WHERE status = 'covered') AS b) AS t
WHERE t.a <> t.b;
