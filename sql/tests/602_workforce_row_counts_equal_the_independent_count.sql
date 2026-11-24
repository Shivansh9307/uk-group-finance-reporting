-- test: for every loaded workforce file the rows loaded equal the data rows the independent recomputation counted
-- marker: localdata
-- requires: raw.workforce_row, raw.workforce_control_expected
SELECT TOP (20) f.dept, f.report_month, f.filename, f.data_rows AS reader_rows, r.n AS loaded_rows, e.data_rows AS independent_rows
FROM raw.workforce_file AS f
CROSS APPLY (SELECT COUNT(*) AS n FROM raw.workforce_row AS w WHERE w.file_id = f.file_id) AS r
CROSS APPLY (SELECT MAX(x.data_rows) AS data_rows, COUNT(DISTINCT x.data_rows) AS kinds
             FROM raw.workforce_control_expected AS x
             WHERE x.dept = f.dept AND x.report_month = f.report_month AND x.filename = f.filename) AS e
WHERE f.load_status = 'loaded'
  AND (f.data_rows <> r.n OR e.data_rows IS NULL OR e.data_rows <> r.n OR e.kinds > 1);
