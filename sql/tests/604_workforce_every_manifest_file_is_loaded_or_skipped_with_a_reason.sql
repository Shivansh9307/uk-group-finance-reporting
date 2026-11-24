-- test: every workforce file is either loaded with at least one data row or skipped with a reason, and a skipped file has no rows
-- marker: localdata
-- requires: raw.workforce_file, raw.workforce_row
SELECT TOP (20) f.dept, f.report_month, f.filename, f.load_status, f.skip_reason, f.data_rows
FROM raw.workforce_file AS f
WHERE f.load_status NOT IN ('loaded', 'skipped')
   OR (f.load_status = 'loaded' AND (f.data_rows = 0 OR f.skip_reason <> '' OR f.n_columns = 0))
   OR (f.load_status = 'skipped' AND (f.skip_reason = '' OR EXISTS (SELECT 1 FROM raw.workforce_row AS r WHERE r.file_id = f.file_id)));
