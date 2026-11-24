-- test: the rows in audit.workforce_mapping_coverage add up to the rows of the primary loaded files, and mapped plus excluded plus unmapped is the total in every department and month
-- marker: localdata
-- requires: audit.workforce_mapping_coverage, raw.workforce_row, raw.workforce_file
SELECT TOP (20) 'total rows differ' AS problem,
       CAST((SELECT SUM(rows_total + rows_empty) FROM audit.workforce_mapping_coverage) AS bigint) AS audit_rows,
       CAST((SELECT COUNT(*) FROM raw.workforce_row AS r JOIN raw.workforce_file AS f ON f.file_id = r.file_id
             WHERE f.is_primary = 1 AND f.load_status = 'loaded') AS bigint) AS raw_rows
WHERE (SELECT SUM(rows_total + rows_empty) FROM audit.workforce_mapping_coverage)
   <> (SELECT COUNT(*) FROM raw.workforce_row AS r JOIN raw.workforce_file AS f ON f.file_id = r.file_id
       WHERE f.is_primary = 1 AND f.load_status = 'loaded')
UNION ALL
SELECT TOP (20) dept + ' ' + report_month, rows_total, rows_mapped + rows_excluded + rows_unmapped
FROM audit.workforce_mapping_coverage
WHERE rows_total <> rows_mapped + rows_excluded + rows_unmapped OR fte_rows_mapped > fte_rows_total;
