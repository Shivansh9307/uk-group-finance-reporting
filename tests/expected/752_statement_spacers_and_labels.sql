-- Independent of the model: the layout table, and whether the statement in SQL has an amount for the line in 2024-25
-- (a spacer has no row). The label of a spacer is its place among the spacers, in zero-width characters.
SELECT l.line_id AS [Line Id], l.line_type AS [Line Type],
       CASE WHEN EXISTS (SELECT 1 FROM dw.v_statement_pnl AS s
                         WHERE s.line_id = l.line_id AND s.financial_year = '2024-25' AND s.outturn IS NOT NULL)
            THEN 0 ELSE 1 END AS amount_is_blank,
       LEN(l.label) AS label_length
FROM dw.statement_line AS l
ORDER BY l.line_key;
