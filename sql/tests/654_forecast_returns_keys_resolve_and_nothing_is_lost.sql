-- test: every row of dw.forecast_return carries the organisation version and durable key of dw.dim_organisation and a known department (never Unknown), and the staged cells split exactly into dw rows and quarantined cells: same cell count, and the exact amount of every return equals dw plus quarantine within the four-decimal rounding of the rows
-- marker: localdata
-- requires: dw.forecast_return, dw.forecast_return_org_map, stg.forecast_return_cell, quarantine.forecast_return_unmapped
SELECT 'row does not agree with the organisation dimension' AS problem, r.financial_year + ' R' + CAST(r.return_no AS varchar(10)) + ' ' + r.organisation_code AS detail
FROM dw.forecast_return AS r
LEFT JOIN dw.dim_organisation AS o ON o.organisation_key = r.organisation_key
WHERE o.organisation_key IS NULL OR o.organisation_key = -1 OR o.durable_key <> r.durable_key OR r.department_key = -1
   OR NOT EXISTS (SELECT 1 FROM dw.dim_department AS d WHERE d.department_key = r.department_key)
GROUP BY r.financial_year, r.return_no, r.organisation_code
UNION ALL
SELECT 'map names a version that does not carry the code or the prefix', m.financial_year + ' ' + m.organisation_code
FROM dw.forecast_return_org_map AS m
JOIN dw.dim_organisation AS o ON o.organisation_key = m.organisation_key
WHERE o.durable_key <> m.durable_key
   OR (m.map_method <> 'prefix' AND o.organisation_code <> m.organisation_code AND m.map_method = 'code, nearest')
   OR (m.map_method = 'prefix' AND LEFT(m.organisation_code, 3) <> o.durable_key)
UNION ALL
SELECT 'organisation code of a cell is neither mapped nor quarantined', c.financial_year + ' ' + c.organisation_code
FROM stg.forecast_return_cell AS c
WHERE NOT EXISTS (SELECT 1 FROM dw.forecast_return_org_map AS m WHERE m.financial_year = c.financial_year AND m.organisation_code = c.organisation_code)
  AND NOT EXISTS (SELECT 1 FROM quarantine.forecast_return_unmapped AS q WHERE q.cell_id = c.cell_id)
GROUP BY c.financial_year, c.organisation_code
UNION ALL
SELECT 'cell count of dw plus quarantine differs from the staged cells', CAST(a.n AS varchar(20)) + ' + ' + CAST(q.n AS varchar(20)) + ' <> ' + CAST(s.n AS varchar(20))
FROM (SELECT SUM(CAST(source_cells AS bigint)) AS n FROM dw.forecast_return) AS a
CROSS JOIN (SELECT COUNT_BIG(*) AS n FROM quarantine.forecast_return_unmapped) AS q
CROSS JOIN (SELECT COUNT_BIG(*) AS n FROM stg.forecast_return_cell) AS s
WHERE a.n + q.n <> s.n
UNION ALL
SELECT 'amount of a return differs between stg and dw plus quarantine', s.financial_year + ' R' + CAST(s.return_no AS varchar(10))
FROM (SELECT financial_year, return_no, SUM(amount_exact) AS amount, COUNT_BIG(*) AS cells FROM stg.forecast_return_cell GROUP BY financial_year, return_no) AS s
LEFT JOIN (SELECT financial_year, return_no, SUM(amount) AS amount, COUNT_BIG(*) AS grain_rows FROM dw.forecast_return GROUP BY financial_year, return_no) AS d
       ON d.financial_year = s.financial_year AND d.return_no = s.return_no
LEFT JOIN (SELECT financial_year, return_no, SUM(amount_exact) AS amount FROM quarantine.forecast_return_unmapped GROUP BY financial_year, return_no) AS q
       ON q.financial_year = s.financial_year AND q.return_no = s.return_no
WHERE ABS(COALESCE(d.amount, 0) + COALESCE(q.amount, 0) - s.amount) > 0.00005 * COALESCE(d.grain_rows, 0) + 0.00005 * s.cells;
