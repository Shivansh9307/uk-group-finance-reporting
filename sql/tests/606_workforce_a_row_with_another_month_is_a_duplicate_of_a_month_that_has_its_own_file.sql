-- test: every row has a month; a row whose own Year and Month are not the month of its file (a carry-over or a mislabel) is quarantined, and the month it names has a file of its own, so quarantining it loses no month
-- marker: localdata
-- requires: stg.workforce_row_class, quarantine.workforce_row, raw.workforce_file
SELECT TOP (20) c.dept, c.report_month, FORMAT(c.period_start, 'yyyy-MM') AS row_month, c.organisation_name, c.status
FROM stg.workforce_row_class AS c
WHERE c.period_start IS NULL
   OR (c.status = 'period_not_file_month'
       AND (NOT EXISTS (SELECT 1 FROM quarantine.workforce_row AS q WHERE q.file_id = c.file_id AND q.source_row = c.source_row
                                                                    AND q.reason_code = 'period_not_file_month')
            OR NOT EXISTS (SELECT 1 FROM raw.workforce_file AS f
                           WHERE f.dept = c.dept AND f.report_month = FORMAT(c.period_start, 'yyyy-MM')
                             AND f.is_primary = 1 AND f.load_status = 'loaded')));
