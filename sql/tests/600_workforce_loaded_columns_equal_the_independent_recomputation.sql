-- test: for every loaded workforce file and every column, the count and exact sum of the numeric cells that the loader holds equal the recomputation that shares no code with the reader, and so does the count of non-numeric cells in the columns the reader recognised (comment and note columns are listed in raw.workforce_ignored_column and not read)
-- marker: localdata
-- requires: raw.workforce_value, raw.workforce_control_expected, raw.workforce_ignored_column
WITH got AS (
    SELECT v.file_id, v.column_index, COUNT_BIG(*) AS n, SUM(v.value) AS s
    FROM raw.workforce_value AS v GROUP BY v.file_id, v.column_index
),
bad AS (
    SELECT q.file_id, q.column_index, COUNT_BIG(*) AS n FROM quarantine.workforce_value AS q GROUP BY q.file_id, q.column_index
)
SELECT TOP (20) f.dept, f.report_month, f.filename, e.column_index,
       e.numeric_cells AS expected_cells, COALESCE(g.n, 0) AS loaded_cells,
       e.value_sum AS expected_sum, COALESCE(g.s, 0) AS loaded_sum,
       e.nonnumeric_cells AS expected_nonnumeric, COALESCE(b.n, 0) AS quarantined
FROM raw.workforce_file AS f
JOIN raw.workforce_control_expected AS e ON e.dept = f.dept AND e.report_month = f.report_month AND e.filename = f.filename
LEFT JOIN got AS g ON g.file_id = f.file_id AND g.column_index = e.column_index
LEFT JOIN bad AS b ON b.file_id = f.file_id AND b.column_index = e.column_index
WHERE f.load_status = 'loaded'
  AND NOT EXISTS (SELECT 1 FROM raw.workforce_ignored_column AS i WHERE i.file_id = f.file_id AND i.column_index = e.column_index)
  AND (COALESCE(g.n, 0) <> e.numeric_cells OR COALESCE(g.s, 0) <> e.value_sum OR (COALESCE(b.n, 0) <> e.nonnumeric_cells AND (g.n IS NOT NULL OR b.n IS NOT NULL)));
