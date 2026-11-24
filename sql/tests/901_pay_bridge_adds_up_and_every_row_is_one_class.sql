-- test: the pay bridge ties and its rows are well formed: in audit.pay_bridge_tie the difference is zero for every department and month; a continuing row has a valid cell on both sides and volume plus rate equals its change in paybill; an entry has no prior value, an exit no current value; a row that is not bridged has a reason and no volume; the grain (department, organisation, month) is unique; the classes have the pinned counts (4,950 continuing, 118 entry, 222 exit, 188 not bridged because the other month's cell is excluded, 2,068 because the department has no valid cell in one of the two months)
-- marker: localdata
-- requires: dw.v_model_pay_bridge, audit.pay_bridge_tie
SELECT CONCAT('tie ', department_key, ' ', month_start) AS what, 'difference is not zero' AS problem
FROM audit.pay_bridge_tie WHERE difference <> 0
UNION ALL
SELECT CONCAT('row ', department_key, ' ', durable_key, ' ', month_start), 'volume plus rate is not the change in paybill, or the class is malformed'
FROM dw.v_model_pay_bridge
WHERE (bridge_class = 'continuing' AND (fte_cur IS NULL OR fte_prior IS NULL OR pay_cur IS NULL OR pay_prior IS NULL
                                        OR fte_cur <= 0 OR fte_prior <= 0 OR volume_org + rate_org <> pay_cur - pay_prior))
   OR (bridge_class = 'entry' AND (fte_cur IS NULL OR pay_cur IS NULL OR pay_prior IS NOT NULL OR volume_org IS NOT NULL))
   OR (bridge_class = 'exit' AND (pay_prior IS NULL OR pay_cur IS NOT NULL OR volume_org IS NOT NULL))
   OR (bridge_class = 'not_bridged' AND (not_bridged_reason IS NULL OR volume_org IS NOT NULL))
   OR (bridge_class <> 'not_bridged' AND not_bridged_reason IS NOT NULL)
   OR bridge_class NOT IN ('continuing', 'entry', 'exit', 'not_bridged')
UNION ALL
SELECT 'grain', CONCAT(COUNT(*), ' rows share a department, organisation and month')
FROM (SELECT department_key, durable_key, month_start FROM dw.v_model_pay_bridge
      GROUP BY department_key, durable_key, month_start HAVING COUNT(*) > 1) AS d
HAVING COUNT(*) > 0
UNION ALL
SELECT CONCAT(e.bridge_class, ' / ', COALESCE(e.reason, '-')), CONCAT('expected ', e.expected_rows, ' rows, found ', COALESCE(a.n, 0))
FROM (VALUES ('continuing', CAST(NULL AS varchar(30)), 4950), ('entry', NULL, 118), ('exit', NULL, 222),
             ('not_bridged', 'comparison_cell_excluded', 188), ('not_bridged', 'department_not_comparable', 2068))
     AS e (bridge_class, reason, expected_rows)
LEFT JOIN (SELECT bridge_class, not_bridged_reason, COUNT(*) AS n FROM dw.v_model_pay_bridge GROUP BY bridge_class, not_bridged_reason) AS a
       ON a.bridge_class = e.bridge_class AND (a.not_bridged_reason = e.reason OR (a.not_bridged_reason IS NULL AND e.reason IS NULL))
WHERE COALESCE(a.n, 0) <> e.expected_rows;
