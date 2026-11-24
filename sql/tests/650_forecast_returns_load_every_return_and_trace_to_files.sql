-- test: the load holds exactly the 83 returns (R0 to R13 for FY2017-18 to FY2020-21 and FY2022-23, R1 to R13 for FY2021-22), each from the family the design names, each file hash equals the manifest, and the source rows of every return equal the records behind its cells
-- marker: localdata
-- requires: raw.forecast_return_file, raw.forecast_return_cell
SELECT 'number of returns is not 83' AS problem, CAST(COUNT(*) AS varchar(40)) AS detail
FROM raw.forecast_return_file HAVING COUNT(*) <> 83
UNION ALL
SELECT 'returns of a year differ from the expected set', f.financial_year + ' ' + CAST(COUNT(*) AS varchar(10)) + ' returns'
FROM raw.forecast_return_file AS f
GROUP BY f.financial_year
HAVING NOT (COUNT(*) = 14 AND MIN(f.return_no) = 0 AND MAX(f.return_no) = 13
         OR f.financial_year = '2021-22' AND COUNT(*) = 13 AND MIN(f.return_no) = 1 AND MAX(f.return_no) = 13)
UNION ALL
SELECT 'wrong family for the year', f.financial_year + ' ' + f.family
FROM raw.forecast_return_file AS f
WHERE f.family <> CASE WHEN f.financial_year IN ('2021-22', '2022-23') THEN 'mfo' ELSE 'extract' END
UNION ALL
SELECT 'a return appears twice', f.financial_year + ' R' + CAST(f.return_no AS varchar(10))
FROM raw.forecast_return_file AS f GROUP BY f.financial_year, f.return_no HAVING COUNT(*) > 1
UNION ALL
SELECT 'file hash differs from the manifest', f.filename
FROM raw.forecast_return_file AS f WHERE f.sha256_file <> f.sha256_manifest
UNION ALL
SELECT 'source rows or cells differ from what the cells say', f.financial_year + ' R' + CAST(f.return_no AS varchar(10))
FROM raw.forecast_return_file AS f
LEFT JOIN (SELECT file_id, SUM(CAST(source_rows AS bigint)) AS n, COUNT(*) AS cells, MIN(first_line) AS lo, MAX(last_line) AS hi
           FROM raw.forecast_return_cell GROUP BY file_id) AS c ON c.file_id = f.file_id
WHERE c.file_id IS NULL OR c.n <> f.source_rows OR c.cells <> f.cells OR c.lo < 1
UNION ALL
SELECT 'a cell is not in its own return or has an impossible line range', CAST(c.cell_id AS varchar(20))
FROM raw.forecast_return_cell AS c JOIN raw.forecast_return_file AS f ON f.file_id = c.file_id
WHERE c.return_no <> f.return_no OR c.first_line > c.last_line OR c.source_rows < 1
UNION ALL
SELECT 'MFO line numbers run past the records read', f.member
FROM raw.forecast_return_cell AS c JOIN raw.forecast_return_file AS f ON f.file_id = c.file_id
WHERE f.family = 'mfo' AND c.last_line > f.source_rows
GROUP BY f.member
UNION ALL
SELECT 'repaired record count differs from the one known broken record (MFO-R05-2022-23)', CAST(SUM(repaired_records) AS varchar(10))
FROM raw.forecast_return_file HAVING SUM(repaired_records) <> 1;
