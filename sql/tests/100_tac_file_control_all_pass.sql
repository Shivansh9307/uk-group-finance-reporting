-- test: every worksheet of every TAC data file passes the file control: rows and exact sum against the independent recomputation, stg against rounded raw, fact against stg, and no worksheet or file is missing on either side
-- marker: localdata
SELECT release, filename, worksheet_name, rows_expected, rows_read, rows_loaded, difference, difference_stg, difference_fact, status
FROM audit.tac_file_control_totals
WHERE status <> 'pass'
UNION ALL
SELECT NULL, NULL, 'files in raw.tac_file', COUNT(*), NULL, NULL, NULL, NULL, NULL, 'expected 12 data files and 6 illustrative forms'
FROM raw.tac_file
HAVING SUM(CASE WHEN file_kind = 'data' THEN 1 ELSE 0 END) <> 12 OR SUM(CASE WHEN file_kind = 'template' THEN 1 ELSE 0 END) <> 6
UNION ALL
SELECT NULL, NULL, 'worksheets', COUNT(*), NULL, NULL, NULL, NULL, NULL, 'a worksheet loaded is not one of the three statements'
FROM raw.tac_worksheet
WHERE loaded = 1 AND LEFT(worksheet_name, 5) NOT IN ('TAC02', 'TAC03', 'TAC05')
HAVING COUNT(*) > 0;
