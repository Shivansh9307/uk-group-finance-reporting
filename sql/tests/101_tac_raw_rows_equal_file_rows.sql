-- test: for every TAC data file the rows read equal the rows loaded plus rejected, the worksheet inventory adds up to the rows of the file, and the staged rows equal the raw rows
-- marker: localdata
SELECT f.filename, f.statement_rows, ISNULL(r.n, 0) AS raw_rows, ISNULL(q.n, 0) AS rejected, ISNULL(s.n, 0) AS staged, 'statement rows do not add up' AS problem
FROM raw.tac_file AS f
LEFT JOIN (SELECT file_id, COUNT_BIG(*) AS n FROM raw.tac_value GROUP BY file_id) AS r ON r.file_id = f.file_id
LEFT JOIN (SELECT file_id, COUNT_BIG(*) AS n FROM quarantine.tac_value GROUP BY file_id) AS q ON q.file_id = f.file_id
LEFT JOIN (SELECT file_id, COUNT_BIG(*) AS n FROM stg.tac_value GROUP BY file_id) AS s ON s.file_id = f.file_id
WHERE f.file_kind = 'data' AND (f.statement_rows <> ISNULL(r.n, 0) + ISNULL(q.n, 0) OR ISNULL(r.n, 0) <> ISNULL(s.n, 0))
UNION ALL
SELECT f.filename, f.data_rows, w.n, NULL, NULL, 'worksheet inventory does not add up to the rows of the file'
FROM raw.tac_file AS f
JOIN (SELECT file_id, SUM(data_rows) AS n FROM raw.tac_worksheet GROUP BY file_id) AS w ON w.file_id = f.file_id
WHERE f.file_kind = 'data' AND f.data_rows <> w.n
UNION ALL
SELECT f.filename, f.total_rows, f.data_rows + f.blank_rows, NULL, NULL, 'rows are not data plus blank'
FROM raw.tac_file AS f
WHERE f.file_kind = 'data' AND f.total_rows <> f.data_rows + f.blank_rows;
