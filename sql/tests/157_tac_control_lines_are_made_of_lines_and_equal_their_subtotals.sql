-- test: a control line is made of statement lines only (never a subtotal or a total), every member is a line of the statement the control line names, and the provider side added from lines equals the provider side added from the published subtotals in every provider-year (total assets = non-current plus current assets, total liabilities = current plus non-current liabilities, total assets employed, total operating income), so summing lines does not double count a subtotal
-- marker: localdata
-- requires: dw.tac_control_member, dw.tac_control_line
SELECT c.control_line AS what, 'control line with no member' AS problem
FROM dw.tac_control_line AS c
WHERE NOT EXISTS (SELECT 1 FROM dw.tac_control_member AS m WHERE m.control_line_key = c.control_line_key)
UNION ALL
SELECT c.control_line + ' ' + l.sub_code, 'member that is a subtotal or a total, or in another statement than the control line'
FROM dw.tac_control_member AS m
JOIN dw.tac_control_line AS c ON c.control_line_key = m.control_line_key
JOIN dw.tac_statutory_line AS l ON l.line_key = m.line_key
WHERE l.line_kind <> 'line' OR l.statement <> c.statement
UNION ALL
-- the lines equal the subtotals, per provider, year and column
SELECT x.control_line + ' ' + x.release + ' ' + x.period_column + ' provider ' + CAST(x.provider_key AS varchar(10)), 'sum of lines differs from the published subtotals'
FROM (
    SELECT c.control_line, f.provider_key, f.release, f.period_column, SUM(f.value) AS from_lines
    FROM dw.tac_fact AS f
    JOIN dw.tac_control_member AS m ON m.line_key = f.line_key
    JOIN dw.tac_control_line AS c ON c.control_line_key = m.control_line_key
    WHERE c.control_line IN ('TOTAL_ASSETS', 'TOTAL_LIABILITIES', 'NET_ASSETS', 'OPERATING_INCOME')
    GROUP BY c.control_line, f.provider_key, f.release, f.period_column
) AS x
JOIN (
    SELECT CASE WHEN l.sub_code IN ('BAL1180', 'BAL1250') THEN 'TOTAL_ASSETS'
                WHEN l.sub_code IN ('BAL1320', 'BAL1390') THEN 'TOTAL_LIABILITIES'
                WHEN l.sub_code = 'BAL1400' THEN 'NET_ASSETS' END AS control_line,
           f.provider_key, f.release, f.period_column, SUM(f.value) AS from_subtotals
    FROM dw.tac_fact AS f JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key
    WHERE l.sub_code IN ('BAL1180', 'BAL1250', 'BAL1320', 'BAL1390', 'BAL1400')
    GROUP BY CASE WHEN l.sub_code IN ('BAL1180', 'BAL1250') THEN 'TOTAL_ASSETS'
                  WHEN l.sub_code IN ('BAL1320', 'BAL1390') THEN 'TOTAL_LIABILITIES'
                  WHEN l.sub_code = 'BAL1400' THEN 'NET_ASSETS' END, f.provider_key, f.release, f.period_column
) AS s ON s.control_line = x.control_line AND s.provider_key = x.provider_key AND s.release = x.release AND s.period_column = x.period_column
WHERE ABS(x.from_lines - s.from_subtotals) >= 0.01
UNION ALL
-- operating income has no printed subtotal on the provider side: it is the sum of its two lines, which is what the group total is
SELECT 'OPERATING_INCOME', 'the two income lines are not the only members'
WHERE (SELECT COUNT(*) FROM dw.tac_control_member AS m JOIN dw.tac_control_line AS c ON c.control_line_key = m.control_line_key WHERE c.control_line = 'OPERATING_INCOME') <> 2
UNION ALL
SELECT 'NET_ASSETS', 'net assets is not assets plus liabilities'
WHERE (SELECT COUNT(*) FROM dw.tac_control_member AS m JOIN dw.tac_control_line AS c ON c.control_line_key = m.control_line_key WHERE c.control_line = 'NET_ASSETS')
   <> (SELECT COUNT(*) FROM dw.tac_control_member AS m JOIN dw.tac_control_line AS c ON c.control_line_key = m.control_line_key WHERE c.control_line IN ('TOTAL_ASSETS', 'TOTAL_LIABILITIES'));
