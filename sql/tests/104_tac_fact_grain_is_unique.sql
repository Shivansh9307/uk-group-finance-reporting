-- test: dw.tac_fact has one row per provider, year, line and column, and one row per source row
-- marker: localdata
SELECT provider_key, release, line_key, period_column, COUNT(*) AS n, 'grain repeated' AS problem
FROM dw.tac_fact GROUP BY provider_key, release, line_key, period_column HAVING COUNT(*) > 1
UNION ALL
SELECT NULL, file_id, source_row, NULL, COUNT(*), 'source row used twice'
FROM dw.tac_fact GROUP BY file_id, source_row HAVING COUNT(*) > 1
UNION ALL
SELECT NULL, NULL, NULL, period_column, COUNT(*), 'column is not CY or PY' FROM dw.tac_fact
WHERE period_column NOT IN ('CY', 'PY') GROUP BY period_column;
