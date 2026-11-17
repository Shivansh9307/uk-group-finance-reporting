-- test: all 9 Estimates workbooks and 7 PESA and SR25 workbooks were read, their hashes equal the manifest, and the rows counted per file equal the rows in the raw tables
SELECT f.file_id, f.edition, f.filename, 'hash differs from the manifest' AS problem
FROM raw.plan_source_file AS f
WHERE f.family IN ('estimates', 'pesa') AND f.sha256_file <> f.sha256_manifest
UNION ALL
SELECT f.file_id, f.edition, f.filename, 'rows_loaded differs from the rows in the raw table'
FROM raw.plan_source_file AS f
WHERE f.family = 'estimates' AND f.rows_loaded <> (SELECT COUNT(*) FROM raw.plan_estimates AS r WHERE r.file_id = f.file_id)
UNION ALL
SELECT f.file_id, f.edition, f.filename, 'rows_loaded differs from the rows in the raw table'
FROM raw.plan_source_file AS f
WHERE f.family = 'pesa' AND f.rows_loaded <> (SELECT COUNT(*) FROM raw.plan_pesa AS r WHERE r.file_id = f.file_id)
UNION ALL
SELECT NULL, NULL, NULL, 'expected 9 Estimates and 7 PESA workbooks, found ' + CAST((SELECT COUNT(*) FROM raw.plan_source_file WHERE family = 'estimates') AS varchar(5))
       + ' and ' + CAST((SELECT COUNT(*) FROM raw.plan_source_file WHERE family = 'pesa') AS varchar(5))
WHERE (SELECT COUNT(*) FROM raw.plan_source_file WHERE family = 'estimates') <> 9
   OR (SELECT COUNT(*) FROM raw.plan_source_file WHERE family = 'pesa') <> 7;
