-- test: the allocated amounts of each rule and year add up to the pool, and the pool used for the comparison is not the one in dw.allocation_pool: it is the sum of the last release's line snapshot (the route of test 942), so the tie cannot be true by construction. Each allocated amount is the pool times its weight within the rounding of the stored amount (0.00006 in GBP thousands, six pence) except on the one rounding row of the year, which is the participant with the largest full-time equivalent (the lowest department number on a tie), and whose adjustment is stored, is within 0.00005 for each participant of the year, and is what makes the sum exact. The year summary says the same. This can fail: a pool that differs, an allocated amount that is not the share, a remainder put on the wrong row or not stored
-- marker: localdata
-- requires: dw.fact_allocation, audit.allocation_year_summary, stg.outturn_line_snapshot, stg.current_structure_map, dw.dim_segment, authored.allocation_rule
WITH last_rel AS (
    SELECT s.period_key / 100 AS fy_start, MAX(s.release_seq) AS release_seq
    FROM stg.outturn_line_snapshot AS s GROUP BY s.period_key / 100
),
pool2 AS (
    SELECT r.rule_id, CONCAT(l.fy_start, '-', RIGHT(CAST(l.fy_start + 1 AS varchar(4)), 2)) AS financial_year, SUM(s.amount) AS pool_amount
    FROM authored.allocation_rule AS r
    JOIN dw.dim_department AS d ON d.department_number = r.pool_department_number AND d.is_current = 1
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_detail_code = r.pool_control_budget_detail_code
    JOIN last_rel AS l ON 1 = 1
    JOIN stg.outturn_line_snapshot AS s ON s.release_seq = l.release_seq AND s.period_key / 100 = l.fy_start AND s.control_budget_key = cb.control_budget_key
    JOIN dw.dim_segment AS sg ON sg.segment_key = s.segment_key
    JOIN stg.current_structure_map AS m ON m.organisation_key = s.organisation_key AND m.sub_segment_code = sg.sub_segment_code
    WHERE m.current_department_key = d.department_key
    GROUP BY r.rule_id, l.fy_start
),
y AS (
    SELECT f.rule_id, f.financial_year, SUM(f.allocated_amount) AS allocated_total, SUM(f.rounding_adjustment) AS adjustment_total,
           SUM(CAST(f.is_rounding_row AS int)) AS rounding_rows, COUNT(*) AS participants, SUM(f.avg_fte) AS fte_total
    FROM dw.fact_allocation AS f GROUP BY f.rule_id, f.financial_year
)
SELECT 'allocated total differs from the pool of the release snapshot' AS problem,
       CONCAT(y.financial_year, ' allocated ', y.allocated_total, ' pool ', p.pool_amount) AS detail
FROM y LEFT JOIN pool2 AS p ON p.rule_id = y.rule_id AND p.financial_year = y.financial_year
WHERE p.pool_amount IS NULL OR y.allocated_total <> p.pool_amount
UNION ALL
SELECT 'the year does not have exactly one rounding row', CONCAT(y.rule_id, ' ', y.financial_year) FROM y WHERE y.rounding_rows <> 1
UNION ALL
SELECT 'the rounding adjustment is larger than half a unit of the last place for each participant', CONCAT(y.rule_id, ' ', y.financial_year)
FROM y WHERE ABS(y.adjustment_total) > 0.00005 * y.participants
UNION ALL
SELECT 'an allocated amount is not the pool times its weight', CONCAT(f.financial_year, ' ', f.department_key)
FROM dw.fact_allocation AS f
JOIN y ON y.rule_id = f.rule_id AND y.financial_year = f.financial_year
WHERE ABS((f.allocated_amount - f.rounding_adjustment) - CAST(f.pool_amount AS decimal(38, 10)) * f.avg_fte / y.fte_total) > 0.00006
UNION ALL
SELECT 'the rounding row is not the participant with the largest full-time equivalent', CONCAT(f.financial_year, ' ', f.department_key)
FROM dw.fact_allocation AS f
JOIN dw.dim_department AS d ON d.department_key = f.department_key
WHERE f.is_rounding_row = 1
  AND EXISTS (SELECT 1 FROM dw.fact_allocation AS g JOIN dw.dim_department AS e ON e.department_key = g.department_key
              WHERE g.rule_id = f.rule_id AND g.financial_year = f.financial_year AND g.department_key <> f.department_key
                AND (g.avg_fte > f.avg_fte OR (g.avg_fte = f.avg_fte AND e.department_number < d.department_number)))
UNION ALL
SELECT 'an adjustment is stored on a row that is not the rounding row', CONCAT(financial_year, ' ', department_key)
FROM dw.fact_allocation WHERE is_rounding_row = 0 AND rounding_adjustment <> 0
UNION ALL
SELECT 'the year summary does not say the same', CONCAT(s.rule_id, ' ', s.financial_year)
FROM audit.allocation_year_summary AS s
JOIN y ON y.rule_id = s.rule_id AND y.financial_year = s.financial_year
JOIN pool2 AS p ON p.rule_id = s.rule_id AND p.financial_year = s.financial_year
WHERE s.difference_to_pool <> 0 OR s.allocated_total <> y.allocated_total OR s.pool_amount <> p.pool_amount
   OR s.rounding_adjustment <> y.adjustment_total OR s.participants <> y.participants;
