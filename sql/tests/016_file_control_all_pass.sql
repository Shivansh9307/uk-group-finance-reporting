-- test: audit.file_control has a row for every data file and none of them fails a measure

SELECT file_id, release, filename, overall_status, sha256_status, rows_status, zero_rows_status,
       amount_sum_status, staged_rows_status, staged_sum_status, twin_status
FROM audit.file_control
WHERE overall_status <> 'pass'
UNION ALL
SELECT NULL, NULL, 'file count differs from raw.oscar_inyear_file', 'fail', NULL, NULL, NULL, NULL, NULL, NULL, NULL
WHERE (SELECT COUNT(*) FROM audit.file_control) <> (SELECT COUNT(*) FROM raw.oscar_inyear_file);
