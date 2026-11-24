-- test: every row of every loaded primary workforce file is in dw.workforce_month (mapped) or in quarantine.workforce_row, never both and never neither; no row is quarantined for want of a map row
-- marker: localdata
-- requires: stg.workforce_row_class, quarantine.workforce_row, raw.workforce_file
SELECT TOP (20) 'row not classified' AS problem, f.dept, f.report_month, r.source_row, CAST(NULL AS varchar(30)) AS status
FROM raw.workforce_row AS r
JOIN raw.workforce_file AS f ON f.file_id = r.file_id
WHERE f.is_primary = 1 AND f.load_status = 'loaded'
  AND NOT EXISTS (SELECT 1 FROM stg.workforce_row_class AS c WHERE c.file_id = r.file_id AND c.source_row = r.source_row)
UNION ALL
SELECT TOP (20) 'mapped row also quarantined', c.dept, c.report_month, c.source_row, c.status
FROM stg.workforce_row_class AS c
JOIN quarantine.workforce_row AS q ON q.file_id = c.file_id AND q.source_row = c.source_row
WHERE c.status = 'mapped'
UNION ALL
SELECT TOP (20) 'unmapped row not quarantined', c.dept, c.report_month, c.source_row, c.status
FROM stg.workforce_row_class AS c
WHERE c.status <> 'mapped'
  AND NOT EXISTS (SELECT 1 FROM quarantine.workforce_row AS q WHERE q.file_id = c.file_id AND q.source_row = c.source_row)
UNION ALL
SELECT TOP (20) 'no map row for the name', c.dept, c.report_month, c.source_row, c.status
FROM stg.workforce_row_class AS c
WHERE c.status = 'no_map_row';
