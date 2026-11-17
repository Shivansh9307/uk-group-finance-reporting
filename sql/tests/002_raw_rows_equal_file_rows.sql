-- test: raw rows equal the data rows of the file for all primary files (loaded + quarantined = read = expected)
-- Counts come from raw.oscar_inyear and quarantine.oscar_inyear themselves, not from the audit table.

SELECT f.release, f.filename, e.data_rows AS expected_rows, f.data_rows AS rows_read,
       ISNULL(r.n, 0) AS raw_rows, ISNULL(q.n, 0) AS quarantined_rows
FROM raw.oscar_inyear_file AS f
JOIN raw.oscar_inyear_control_expected AS e ON e.release = f.release AND e.filename = f.filename
LEFT JOIN (SELECT file_id, COUNT_BIG(*) AS n FROM raw.oscar_inyear GROUP BY file_id) AS r ON r.file_id = f.file_id
LEFT JOIN (SELECT file_id, COUNT_BIG(*) AS n FROM quarantine.oscar_inyear GROUP BY file_id) AS q ON q.file_id = f.file_id
WHERE f.primary_for_release = 'Y'
  AND (ISNULL(r.n, 0) <> e.data_rows
       OR f.data_rows <> e.data_rows
       OR ISNULL(r.n, 0) + ISNULL(q.n, 0) <> f.data_rows);
