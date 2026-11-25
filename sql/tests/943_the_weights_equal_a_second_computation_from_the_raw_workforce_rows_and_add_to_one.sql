-- test: the allocation weights equal a second computation from the raw rows of dw.workforce_month: the valid cells are found again here (full-time equivalent and paybill both above zero and the cell not on the list of cells left out of the pay bridge), the department of a cell is the organisation version in force found by a window function, a department-year is the average of its monthly sums over the months it has a cell, the departments taking part are those with at least the rule's minimum months, the set of participants and the months present are equal both ways, the average full-time equivalent agrees to 0.0001 and the weight to 0.00000001, and the weights of each rule and year add to 1 within 0.000000001. This can fail: a wrong month, a wrong department, an excluded cell counted, a department kept or dropped on the wrong side of the minimum
-- marker: localdata
-- requires: dw.fact_allocation, audit.allocation_participation, dw.workforce_month, audit.pay_excluded_cell, authored.allocation_rule, dw.department_reported_number
WITH f AS (
    SELECT w.durable_key, w.month_start, w.report_month,
           MAX(CASE WHEN w.measure_key = 'payroll_fte' THEN w.value END) AS fte,
           MAX(CASE WHEN w.measure_key = 'payroll_paybill_gbp' THEN w.value END) AS paybill
    FROM dw.workforce_month AS w
    WHERE w.measure_key IN ('payroll_fte', 'payroll_paybill_gbp')
    GROUP BY w.durable_key, w.month_start, w.report_month
),
v AS (
    SELECT f.* FROM f
    WHERE f.fte > 0 AND f.paybill > 0
      AND NOT EXISTS (SELECT 1 FROM audit.pay_excluded_cell AS x WHERE x.durable_key = f.durable_key AND x.month_start = f.month_start)
),
ver AS (
    SELECT o.durable_key, o.valid_from_release, d.department_number,
           ROW_NUMBER() OVER (PARTITION BY o.durable_key ORDER BY o.valid_from_release) AS first_rank
    FROM dw.dim_organisation AS o
    JOIN dw.dim_department AS d ON d.department_key = o.department_key
),
cell AS (
    SELECT v.durable_key, v.month_start, v.fte,
           COALESCE(
               (SELECT TOP (1) x.department_number FROM ver AS x
                WHERE x.durable_key = v.durable_key AND x.valid_from_release <= v.report_month
                ORDER BY x.valid_from_release DESC),
               (SELECT x.department_number FROM ver AS x WHERE x.durable_key = v.durable_key AND x.first_rank = 1)) AS department_number
    FROM v
),
dm AS (   -- one department and month
    SELECT r.current_department_key AS department_key, c.month_start, SUM(c.fte) AS fte
    FROM cell AS c
    JOIN dw.department_reported_number AS r ON r.reported_department_number = c.department_number
    GROUP BY r.current_department_key, c.month_start
),
dy AS (   -- one department and financial year
    SELECT department_key,
           CASE WHEN MONTH(month_start) >= 4 THEN YEAR(month_start) ELSE YEAR(month_start) - 1 END AS fy_start,
           COUNT(*) AS months_present, SUM(fte) AS fte_sum
    FROM dm GROUP BY department_key, CASE WHEN MONTH(month_start) >= 4 THEN YEAR(month_start) ELSE YEAR(month_start) - 1 END
),
ex AS (
    SELECT r.rule_id, CONCAT(y.fy_start, '-', RIGHT(CAST(y.fy_start + 1 AS varchar(4)), 2)) AS financial_year, y.department_key,
           y.months_present, CAST(y.fte_sum AS decimal(38, 10)) / y.months_present AS avg_fte
    FROM dy AS y
    JOIN authored.allocation_rule AS r
      ON CONCAT(y.fy_start, '-', RIGHT(CAST(y.fy_start + 1 AS varchar(4)), 2)) BETWEEN r.first_financial_year AND r.last_financial_year
    WHERE y.months_present >= r.min_months
),
et AS (
    SELECT ex.*, SUM(ex.avg_fte) OVER (PARTITION BY ex.rule_id, ex.financial_year) AS total_fte FROM ex
)
SELECT 'participant on one side only' AS problem, CONCAT(COALESCE(f.financial_year, e.financial_year), ' ', COALESCE(f.department_key, e.department_key)) AS detail
FROM dw.fact_allocation AS f
FULL JOIN et AS e ON e.rule_id = f.rule_id AND e.financial_year = f.financial_year AND e.department_key = f.department_key
WHERE f.rule_id IS NULL OR e.rule_id IS NULL
UNION ALL
SELECT 'months or average full-time equivalent differ', CONCAT(f.financial_year, ' ', f.department_key)
FROM dw.fact_allocation AS f
JOIN et AS e ON e.rule_id = f.rule_id AND e.financial_year = f.financial_year AND e.department_key = f.department_key
WHERE f.months_present <> e.months_present OR ABS(f.avg_fte - e.avg_fte) > 0.0001
UNION ALL
SELECT 'weight differs', CONCAT(f.financial_year, ' ', f.department_key)
FROM dw.fact_allocation AS f
JOIN et AS e ON e.rule_id = f.rule_id AND e.financial_year = f.financial_year AND e.department_key = f.department_key
WHERE ABS(CAST(f.weight AS float) - CAST(e.avg_fte AS float) / CAST(e.total_fte AS float)) > 0.00000001
UNION ALL
SELECT 'weights do not add to 1', CONCAT(rule_id, ' ', financial_year)
FROM dw.fact_allocation GROUP BY rule_id, financial_year HAVING ABS(SUM(weight) - 1) > 0.000000001
UNION ALL
SELECT 'a weight is not in (0, 1]', CONCAT(financial_year, ' ', department_key) FROM dw.fact_allocation WHERE weight <= 0 OR weight > 1
UNION ALL
SELECT 'the participation table and the fact disagree on who takes part', CONCAT(a.financial_year, ' ', a.department_key)
FROM audit.allocation_participation AS a
WHERE CASE WHEN a.status = 'participant' THEN 1 ELSE 0 END
   <> CASE WHEN EXISTS (SELECT 1 FROM dw.fact_allocation AS f
                        WHERE f.rule_id = a.rule_id AND f.financial_year = a.financial_year AND f.department_key = a.department_key)
           THEN 1 ELSE 0 END;
