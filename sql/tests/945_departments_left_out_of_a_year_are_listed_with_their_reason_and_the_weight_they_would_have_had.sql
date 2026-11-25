-- test: every department with a valid payroll cell in a year of the rule has a row in the participation table, a department takes part exactly when it has at least the rule's minimum months, a department left out for too few months has the weight it would have had (its full-time equivalent over the participants' plus its own) and no allocation row, a participant has no such weight, and the year summary counts the participants, the departments left out for too few months, their share and the live departments with no workforce cell at all, each worked out again here from the participation table and the department dimension
-- marker: localdata
-- requires: audit.allocation_participation, audit.allocation_year_summary, dw.fact_allocation, dw.v_pay_cell, authored.allocation_rule, dw.dim_department
WITH cells AS (
    SELECT DISTINCT c.department_key,
           CASE WHEN MONTH(c.month_start) >= 4 THEN YEAR(c.month_start) ELSE YEAR(c.month_start) - 1 END AS fy_start
    FROM dw.v_pay_cell AS c WHERE c.cell_status = 'valid'
),
yrs AS (
    SELECT c.department_key, CONCAT(c.fy_start, '-', RIGHT(CAST(c.fy_start + 1 AS varchar(4)), 2)) AS financial_year
    FROM cells AS c
),
part AS (
    SELECT a.*, SUM(CASE WHEN a.status = 'participant' THEN a.avg_fte END) OVER (PARTITION BY a.rule_id, a.financial_year) AS part_fte
    FROM audit.allocation_participation AS a
)
SELECT 'a department with a valid cell in a year of the rule has no participation row' AS problem, CONCAT(y.financial_year, ' ', y.department_key) AS detail
FROM yrs AS y
JOIN authored.allocation_rule AS r ON y.financial_year BETWEEN r.first_financial_year AND r.last_financial_year
WHERE NOT EXISTS (SELECT 1 FROM audit.allocation_participation AS a
                  WHERE a.rule_id = r.rule_id AND a.financial_year = y.financial_year AND a.department_key = y.department_key)
UNION ALL
SELECT 'status does not follow the minimum months', CONCAT(a.financial_year, ' ', a.department_key)
FROM audit.allocation_participation AS a JOIN authored.allocation_rule AS r ON r.rule_id = a.rule_id
WHERE (a.status = 'participant' AND a.months_present < r.min_months) OR (a.status = 'too_few_months' AND a.months_present >= r.min_months)
UNION ALL
SELECT 'a department left out has an allocation row', CONCAT(a.financial_year, ' ', a.department_key)
FROM audit.allocation_participation AS a
WHERE a.status = 'too_few_months'
  AND EXISTS (SELECT 1 FROM dw.fact_allocation AS f WHERE f.rule_id = a.rule_id AND f.financial_year = a.financial_year AND f.department_key = a.department_key)
UNION ALL
SELECT 'the weight a department left out would have had is wrong', CONCAT(p.financial_year, ' ', p.department_key)
FROM part AS p
WHERE (p.status = 'too_few_months' AND (p.would_be_weight IS NULL OR p.would_be_weight <= 0 OR p.would_be_weight >= 1
        OR ABS(CAST(p.would_be_weight AS float) - CAST(p.avg_fte AS float) / (CAST(p.part_fte AS float) + CAST(p.avg_fte AS float))) > 0.000000001))
   OR (p.status = 'participant' AND p.would_be_weight IS NOT NULL)
UNION ALL
SELECT 'the year summary counts differ', CONCAT(s.rule_id, ' ', s.financial_year)
FROM audit.allocation_year_summary AS s
WHERE s.participants <> (SELECT COUNT(*) FROM audit.allocation_participation AS a
                         WHERE a.rule_id = s.rule_id AND a.financial_year = s.financial_year AND a.status = 'participant')
   OR s.too_few_months_departments <> (SELECT COUNT(*) FROM audit.allocation_participation AS a
                                       WHERE a.rule_id = s.rule_id AND a.financial_year = s.financial_year AND a.status = 'too_few_months')
   OR s.no_workforce_departments <> (SELECT COUNT(*) FROM dw.dim_department AS d
                                     WHERE d.is_current = 1 AND d.member_type = 'Department'
                                       AND d.department_key <> (SELECT TOP (1) pool_department_key FROM dw.allocation_pool AS pl WHERE pl.rule_id = s.rule_id)
                                       AND NOT EXISTS (SELECT 1 FROM yrs AS y WHERE y.department_key = d.department_key AND y.financial_year = s.financial_year))
   OR ABS(CAST(s.too_few_months_weight_share AS float)
          - COALESCE((SELECT SUM(CAST(a.avg_fte AS float)) FROM audit.allocation_participation AS a
                      WHERE a.rule_id = s.rule_id AND a.financial_year = s.financial_year AND a.status = 'too_few_months'), 0)
            / (SELECT SUM(CAST(a.avg_fte AS float)) FROM audit.allocation_participation AS a WHERE a.rule_id = s.rule_id AND a.financial_year = s.financial_year)) > 0.000000001;
