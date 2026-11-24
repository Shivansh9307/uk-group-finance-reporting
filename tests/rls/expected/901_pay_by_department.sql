-- requires: dw.workforce_month, audit.workforce_row_arithmetic
-- Independent of the model views and of dw.v_pay_*: the bridge is rebuilt here from dw.workforce_month, the organisation
-- versions and the arithmetic audit, with its own joins. A cell is valid when its full-time equivalent and paybill are above
-- zero and no published row behind it is listed in audit.workforce_row_arithmetic (full-time equivalent or paybill check).
-- The department is the current-structure department of the organisation version with the latest start on or before the
-- month (the first version when the month is before every start). A month is compared with the same month a year earlier.
-- The cells are held in temporary tables so that every join below is an equality on a column.
SET NOCOUNT ON;
DROP TABLE IF EXISTS #cell, #flagged, #located, #good, #bad;
SELECT w.durable_key, w.month_start,
       MAX(CASE WHEN w.measure_key = 'payroll_fte' THEN w.value END) AS fte,
       MAX(CASE WHEN w.measure_key = 'payroll_paybill_gbp' THEN w.value END) AS pay
INTO #cell
FROM dw.workforce_month AS w
WHERE w.measure_key IN ('payroll_fte', 'payroll_paybill_gbp')
GROUP BY w.durable_key, w.month_start;
SELECT DISTINCT k.durable_key, k.period_start AS month_start
INTO #flagged
FROM audit.workforce_row_arithmetic AS a
JOIN raw.workforce_file AS f ON f.dept = a.dept AND f.report_month = a.report_month AND f.filename = a.filename
JOIN stg.workforce_row_class AS k ON k.file_id = f.file_id AND k.source_row = a.source_row AND k.status = 'mapped'
WHERE a.check_key IN ('payroll_fte', 'payroll_paybill_gbp');
WITH versioned AS (
    SELECT c.durable_key, c.month_start, c.fte, c.pay, d.department_number,
           ROW_NUMBER() OVER (PARTITION BY c.durable_key, c.month_start
                              ORDER BY CASE WHEN o.valid_from_release <= CONVERT(char(7), c.month_start, 126) THEN 0 ELSE 1 END,
                                       CASE WHEN o.valid_from_release <= CONVERT(char(7), c.month_start, 126) THEN -o.version_no ELSE o.version_no END) AS rn
    FROM #cell AS c
    JOIN dw.dim_organisation AS o ON o.durable_key = c.durable_key
    JOIN dw.dim_department AS d ON d.department_key = o.department_key
)
SELECT v.durable_key, v.month_start, v.fte, v.pay, r.current_department_key AS dept,
       CASE WHEN v.fte > 0 AND v.pay > 0 AND fl.durable_key IS NULL THEN 1 ELSE 0 END AS is_valid,
       DATEADD(YEAR, -1, v.month_start) AS prev_month, DATEADD(YEAR, 1, v.month_start) AS next_month
INTO #located
FROM versioned AS v
JOIN dw.department_reported_number AS r ON r.reported_department_number = v.department_number
LEFT JOIN #flagged AS fl ON fl.durable_key = v.durable_key AND fl.month_start = v.month_start
WHERE v.rn = 1;
SELECT durable_key, month_start, dept, fte, pay, prev_month, next_month INTO #good FROM #located WHERE is_valid = 1;
SELECT durable_key, month_start, prev_month, next_month INTO #bad FROM #located WHERE is_valid = 0;
CREATE UNIQUE CLUSTERED INDEX ix_good ON #good (durable_key, month_start, dept);
CREATE CLUSTERED INDEX ix_bad ON #bad (durable_key, month_start);
WITH good AS (SELECT * FROM #good),
bad AS (SELECT * FROM #bad),
dept_month AS (SELECT DISTINCT dept, month_start FROM good),
-- the row of each valid cell in its own (later) month: compared with the cell of the same organisation and department a year earlier
cur_side AS (
    SELECT g.dept, g.durable_key, g.month_start,
           CASE WHEN p.durable_key IS NOT NULL THEN 'continuing'
                WHEN EXISTS (SELECT 1 FROM bad AS b WHERE b.durable_key = g.durable_key AND b.month_start = g.prev_month)
                     THEN 'not_bridged'
                ELSE 'entry' END AS cls,
           CAST(CASE WHEN p.durable_key IS NULL AND EXISTS (SELECT 1 FROM bad AS b WHERE b.durable_key = g.durable_key AND b.month_start = g.prev_month) THEN 'comparison_cell_excluded' END AS varchar(30)) AS reason,
           g.fte AS fte_cur, g.pay AS pay_cur, p.fte AS fte_prior, p.pay AS pay_prior
    FROM good AS g
    LEFT JOIN good AS p ON p.durable_key = g.durable_key AND p.dept = g.dept AND p.month_start = g.prev_month
),
-- the row of each valid cell of a year earlier that has no valid cell of the same organisation and department in the later month
prior_side AS (
    SELECT p.dept, p.durable_key, p.next_month AS month_start,
           CASE WHEN EXISTS (SELECT 1 FROM bad AS b WHERE b.durable_key = p.durable_key AND b.month_start = p.next_month)
                     THEN 'not_bridged' ELSE 'exit' END AS cls,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM bad AS b WHERE b.durable_key = p.durable_key AND b.month_start = p.next_month) THEN 'comparison_cell_excluded' END AS varchar(30)) AS reason,
           CAST(NULL AS decimal(19, 4)) AS fte_cur, CAST(NULL AS decimal(19, 4)) AS pay_cur, p.fte AS fte_prior, p.pay AS pay_prior
    FROM good AS p
    WHERE NOT EXISTS (SELECT 1 FROM good AS g WHERE g.durable_key = p.durable_key AND g.dept = p.dept AND g.month_start = p.next_month)
),
br AS (
    SELECT x.dept AS department_key, x.durable_key, x.month_start,
           CASE WHEN x.cls <> 'not_bridged' AND NOT (EXISTS (SELECT 1 FROM dept_month AS a WHERE a.dept = x.dept AND a.month_start = x.month_start)
                                                     AND EXISTS (SELECT 1 FROM dept_month AS b WHERE b.dept = x.dept AND b.month_start = DATEADD(YEAR, -1, x.month_start)))
                THEN 'not_bridged' ELSE x.cls END AS cls,
           CAST(CASE WHEN x.cls <> 'not_bridged' AND NOT (EXISTS (SELECT 1 FROM dept_month AS a WHERE a.dept = x.dept AND a.month_start = x.month_start)
                                                     AND EXISTS (SELECT 1 FROM dept_month AS b WHERE b.dept = x.dept AND b.month_start = DATEADD(YEAR, -1, x.month_start)))
                     THEN 'department_not_comparable' ELSE x.reason END AS varchar(30)) AS reason,
           x.fte_cur, x.pay_cur, x.fte_prior, x.pay_prior
    FROM (SELECT * FROM cur_side UNION ALL SELECT * FROM prior_side) AS x
),
bridge AS (
    SELECT br.*,
           -- the volume of one organisation is evaluated with operands of 10 decimal places and rounded to 4, the rule the model's data is held in
           CAST(CASE WHEN cls = 'continuing' THEN CAST(fte_cur - fte_prior AS decimal(24, 10)) * CAST(pay_prior AS decimal(24, 10)) / CAST(fte_prior AS decimal(24, 10)) END AS decimal(19, 4)) AS vol_org
    FROM br
),
bridge2 AS (
    SELECT bridge.*, CAST(CASE WHEN cls = 'continuing' THEN pay_cur - pay_prior - vol_org END AS decimal(19, 4)) AS rate_org
    FROM bridge
)
,
m AS (
    SELECT g.dept, SUM(g.pay) AS pay, SUM(g.fte) AS fte
    FROM good AS g
    JOIN dw.dim_department AS d ON d.department_key = g.dept
    WHERE g.month_start >= '2025-04-01' AND g.month_start <= '2026-03-01'
      AND d.department_number IN (SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user})
    GROUP BY g.dept
)
SELECT d.department_name AS department, CAST(m.pay AS decimal(38, 4)) AS pay_paybill, CAST(m.pay / m.fte AS decimal(38, 4)) AS pay_average_cost
FROM m
JOIN dw.dim_department AS d ON d.department_key = m.dept
ORDER BY department;
