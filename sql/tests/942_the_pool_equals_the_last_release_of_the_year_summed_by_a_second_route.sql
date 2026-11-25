-- test: the pool of each year equals a second computation that does not read dw.fact_outturn or any revision delta: the line-level snapshot of the last release that reports the year (stg.outturn_line_snapshot, what the release file states), the lines of the pool department in the pool control budget detail found through the current-structure map and the sub-segment code, summed. This can fail: a delta that is missing or doubled, a wrong release, a line sent to the wrong department, a wrong control budget
-- marker: localdata
-- requires: dw.allocation_pool, stg.outturn_line_snapshot, stg.current_structure_map, dw.dim_segment, dw.dim_department, dw.dim_control_budget, authored.allocation_rule
WITH last_rel AS (
    SELECT s.period_key / 100 AS fy_start, MAX(s.release_seq) AS release_seq
    FROM stg.outturn_line_snapshot AS s
    GROUP BY s.period_key / 100
),
second AS (
    SELECT r.rule_id,
           CONCAT(l.fy_start, '-', RIGHT(CAST(l.fy_start + 1 AS varchar(4)), 2)) AS financial_year,
           SUM(s.amount) AS pool_amount
    FROM authored.allocation_rule AS r
    JOIN dw.dim_department AS d ON d.department_number = r.pool_department_number AND d.is_current = 1
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_detail_code = r.pool_control_budget_detail_code
    JOIN last_rel AS l ON 1 = 1
    JOIN stg.outturn_line_snapshot AS s ON s.release_seq = l.release_seq AND s.period_key / 100 = l.fy_start
                                       AND s.control_budget_key = cb.control_budget_key
    JOIN dw.dim_segment AS sg ON sg.segment_key = s.segment_key
    JOIN stg.current_structure_map AS m ON m.organisation_key = s.organisation_key AND m.sub_segment_code = sg.sub_segment_code
    WHERE m.current_department_key = d.department_key
    GROUP BY r.rule_id, l.fy_start
)
SELECT 'pool on one side only' AS problem, COALESCE(p.financial_year, e.financial_year) AS detail
FROM dw.allocation_pool AS p
FULL JOIN second AS e ON e.rule_id = p.rule_id AND e.financial_year = p.financial_year
JOIN authored.allocation_rule AS r ON r.rule_id = COALESCE(p.rule_id, e.rule_id)
WHERE (p.rule_id IS NULL AND e.financial_year BETWEEN r.first_financial_year AND r.last_financial_year) OR (e.rule_id IS NULL)
UNION ALL
SELECT 'pool differs from the last release of the year', CONCAT(p.financial_year, ' pool ', p.pool_amount, ' recomputed ', e.pool_amount)
FROM dw.allocation_pool AS p
JOIN second AS e ON e.rule_id = p.rule_id AND e.financial_year = p.financial_year
WHERE p.pool_amount <> e.pool_amount
UNION ALL
SELECT 'a pool is not positive', p.financial_year FROM dw.allocation_pool AS p WHERE p.pool_amount <= 0;
