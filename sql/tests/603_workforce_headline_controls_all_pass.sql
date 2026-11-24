-- test: every row of audit.workforce_file_control_totals passes with a difference of exactly 0, and the table has a row for every loaded file
-- marker: localdata
-- requires: audit.workforce_file_control_totals, raw.workforce_file
SELECT TOP (20) dept, report_month, filename, measure_key, cells_expected, cells_loaded, difference_sum, status
FROM audit.workforce_file_control_totals
WHERE status <> 'pass' OR difference_sum <> 0
UNION ALL
SELECT TOP (20) f.dept, f.report_month, f.filename, 'no headline column', 0, 0, 0, 'missing'
FROM raw.workforce_file AS f
WHERE f.load_status = 'loaded'
  AND NOT EXISTS (SELECT 1 FROM audit.workforce_file_control_totals AS a
                  WHERE a.dept = f.dept AND a.report_month = f.report_month AND a.filename = f.filename);
