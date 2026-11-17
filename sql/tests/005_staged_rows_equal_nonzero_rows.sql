-- test: staged rows equal data rows minus exact-zero rows, and the raw zero-row count equals the control table
-- A row is zero when its exact amount is zero. Amounts that are only float residue (about 1e-14)
-- are not zero and stay in the staged table with an amount of 0.0000.

SELECT f.release, f.filename,
       e.data_rows - e.zero_rows AS expected_staged_rows,
       ISNULL(s.n, 0) AS staged_rows,
       e.zero_rows AS expected_zero_rows,
       ISNULL(z.n, 0) AS raw_zero_rows
FROM raw.oscar_inyear_file AS f
JOIN raw.oscar_inyear_control_expected AS e ON e.release = f.release AND e.filename = f.filename
LEFT JOIN (SELECT release, COUNT_BIG(*) AS n FROM stg.inyear_snapshot GROUP BY release) AS s ON s.release = f.release
LEFT JOIN (
    SELECT file_id, COUNT_BIG(*) AS n
    FROM raw.oscar_inyear
    WHERE amount_whole = 0 AND amount_frac = 0
    GROUP BY file_id
) AS z ON z.file_id = f.file_id
WHERE f.primary_for_release = 'Y'
  AND (ISNULL(s.n, 0) <> e.data_rows - e.zero_rows OR ISNULL(z.n, 0) <> e.zero_rows);
