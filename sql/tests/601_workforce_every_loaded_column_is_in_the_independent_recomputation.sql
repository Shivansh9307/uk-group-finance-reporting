-- test: every column that holds a loaded value (or a quarantined cell) in a loaded workforce file has a row in the independent recomputation, and every loaded file has one
-- marker: localdata
-- requires: raw.workforce_value, raw.workforce_control_expected
SELECT TOP (20) f.dept, f.report_month, f.filename, c.column_index
FROM raw.workforce_file AS f
JOIN (
    SELECT file_id, column_index FROM raw.workforce_value
    UNION SELECT file_id, column_index FROM quarantine.workforce_value
) AS c ON c.file_id = f.file_id
WHERE f.load_status = 'loaded'
  AND NOT EXISTS (SELECT 1 FROM raw.workforce_control_expected AS e
                  WHERE e.dept = f.dept AND e.report_month = f.report_month AND e.filename = f.filename
                    AND e.column_index = c.column_index)
UNION ALL
SELECT TOP (20) f.dept, f.report_month, f.filename, -1
FROM raw.workforce_file AS f
WHERE f.load_status = 'loaded'
  AND NOT EXISTS (SELECT 1 FROM raw.workforce_control_expected AS e
                  WHERE e.dept = f.dept AND e.report_month = f.report_month AND e.filename = f.filename);
