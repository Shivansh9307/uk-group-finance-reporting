-- test: for every subtotal and total line and every year, the line equals the sum of the members its definition lists, taken one level down (a member that is itself a subtotal counts as a whole), and a member list never reaches a detail line by two paths
WITH edge AS (
    SELECT l.line_id, m.value AS member_id
    FROM dw.statement_line AS l CROSS APPLY STRING_SPLIT(l.members, ' ') AS m
    WHERE l.members <> '' AND m.value <> ''
), summed AS (
    SELECT e.line_id, s.financial_year, SUM(s.outturn_as_reported) AS amt, COUNT(*) AS n
    FROM edge AS e JOIN dw.v_statement_pnl AS s ON s.line_id = e.member_id
    GROUP BY e.line_id, s.financial_year
)
SELECT 'line differs from its members' AS problem, s.line_id AS detail, s.financial_year AS detail2
FROM dw.v_statement_pnl AS s
JOIN dw.statement_line AS l ON l.line_id = s.line_id AND l.line_type IN ('subtotal', 'total')
LEFT JOIN summed AS x ON x.line_id = s.line_id AND x.financial_year = s.financial_year
WHERE s.outturn_as_reported IS NOT NULL AND (x.amt IS NULL OR ABS(x.amt - s.outturn_as_reported) > 0.0001)
UNION ALL
SELECT 'detail line reached by two paths', l.line_id, CAST(m.detail_line_key AS nvarchar(20))
FROM dw.statement_line_member AS m JOIN dw.statement_line AS l ON l.line_key = m.line_key
WHERE m.path_count <> 1
UNION ALL
SELECT 'spacer with an amount', s.line_id, s.financial_year
FROM dw.v_statement_pnl AS s JOIN dw.statement_line AS l ON l.line_id = s.line_id
WHERE l.line_type = 'spacer';
