-- requires: dw.tac_fact
-- Independent of the model: the current-year column of the balance sheet from dw.tac_fact, by file year and section. A
-- section adds its lines of kind line; a section that has one line only (the two running totals) is that line as published.
WITH sec AS (
    SELECT l.line_key, l.section, l.line_kind, COUNT(*) OVER (PARTITION BY l.statement, l.section) AS lines_in_section
    FROM dw.tac_statutory_line AS l
    WHERE l.statement = 'SoFP'
)
SELECT f.release AS [Financial Year], s.section AS [Section],
       CAST(SUM(CASE WHEN s.line_kind = 'line' OR s.lines_in_section = 1 THEN f.value END) AS decimal(38, 4)) AS closing_balance,
       COUNT_BIG(DISTINCT f.provider_key) AS providers_reporting
FROM dw.tac_fact AS f
JOIN sec AS s ON s.line_key = f.line_key
WHERE f.period_column = 'CY'
GROUP BY f.release, s.section
ORDER BY f.release, s.section;
