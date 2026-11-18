-- test: every line has a distinct label (spacers differ by zero-width characters only), an income-positive line holds income accounts only, and the presented amount is the reported amount times the sign factor
SELECT 'two lines share a label' AS problem, label AS detail
FROM dw.statement_line GROUP BY label HAVING COUNT(*) > 1
UNION ALL
SELECT 'spacer label is not only zero-width characters', line_id
FROM dw.statement_line
WHERE line_type = 'spacer' AND (REPLACE(label, NCHAR(8203), N'') <> N'' OR DATALENGTH(label) = 0)
UNION ALL
SELECT 'label of a real line holds a zero-width character', line_id
FROM dw.statement_line WHERE line_type <> 'spacer' AND CHARINDEX(NCHAR(8203), label) > 0
UNION ALL
SELECT 'income-positive line holds an account that is not income', l.line_id
FROM dw.statement_line AS l
JOIN dw.statement_line_member AS m ON m.line_key = l.line_key
JOIN dw.account_statement_line AS s ON s.line_key = m.detail_line_key
JOIN dw.dim_account AS a ON a.account_key = s.account_key
WHERE l.sign_presentation = 'income positive' AND a.flow <> 'Income'
GROUP BY l.line_id
UNION ALL
SELECT 'sign factor does not follow the presentation', line_id
FROM dw.statement_line
WHERE (sign_presentation = 'income positive' AND sign_factor <> -1) OR (sign_presentation = 'as reported' AND sign_factor <> 1)
UNION ALL
SELECT 'presented amount is not the reported amount times the sign factor', s.line_id + ' ' + s.financial_year
FROM dw.v_statement_pnl AS s JOIN dw.statement_line AS l ON l.line_id = s.line_id
WHERE s.outturn IS NOT NULL AND ABS(s.outturn - s.outturn_as_reported * l.sign_factor) > 0.0001;
