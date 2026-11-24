-- requires: dw.tac_fact
-- Independent of the model: from dw.tac_fact, current-year column. Balance sheet: the lines of each block added, and
-- the value of the block's published subtotal line (BAL1180, BAL1250, BAL1320, BAL1390); the two are expected to be
-- the same number. Income statement: the lines of kind line added, and every row added, subtotals and totals too.
SELECT N'balance sheet block: lines added against the published subtotal' AS [case], f.release AS [Financial Year],
       l.section AS [Section],
       CAST(SUM(CASE WHEN l.line_kind = 'line' THEN f.value END) AS decimal(38, 4)) AS lines_or_amount,
       CAST(SUM(CASE WHEN l.line_kind = 'subtotal' THEN f.value END) AS decimal(38, 4)) AS published_or_every_row
FROM dw.tac_fact AS f
JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key
WHERE f.period_column = 'CY' AND l.statement = 'SoFP'
  AND l.section IN ('Non-current assets', 'Current assets', 'Current liabilities', 'Non-current liabilities')
GROUP BY f.release, l.section
UNION ALL
SELECT N'income statement: lines only against every row', f.release, N'All sections',
       CAST(SUM(CASE WHEN l.line_kind = 'line' THEN f.value END) AS decimal(38, 4)),
       CAST(SUM(f.value) AS decimal(38, 4))
FROM dw.tac_fact AS f
JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key
WHERE f.period_column = 'CY' AND l.statement = 'SoCI'
GROUP BY f.release
ORDER BY 1, 2, 3;
