-- test: audit.workforce_row_arithmetic lists exactly 18 payroll full-time equivalent, 21 payroll headcount and 26 payroll paybill rows whose published total is not the sum of their components (these are source errors, not load errors; a different count means the load or the thresholds changed)
-- marker: localdata
-- requires: audit.workforce_row_arithmetic
SELECT e.check_key, e.expected_findings, COALESCE(a.n, 0) AS findings
FROM (VALUES ('payroll_fte', 18), ('payroll_headcount', 21), ('payroll_paybill_gbp', 26)) AS e (check_key, expected_findings)
LEFT JOIN (SELECT check_key, COUNT(*) AS n FROM audit.workforce_row_arithmetic GROUP BY check_key) AS a ON a.check_key = e.check_key
WHERE COALESCE(a.n, 0) <> e.expected_findings
UNION ALL
SELECT check_key, 0, COUNT(*) FROM audit.workforce_row_arithmetic
WHERE check_key NOT IN ('payroll_fte', 'payroll_headcount', 'payroll_paybill_gbp') GROUP BY check_key;
