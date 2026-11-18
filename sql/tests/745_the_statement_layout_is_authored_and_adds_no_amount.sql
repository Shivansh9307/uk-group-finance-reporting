-- test: the statement objects are labelled authored and hold no amount column of any type, and the Unknown account is mapped once
SELECT 'statement table without an AUTHORED description' AS problem, t.name AS detail
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
LEFT JOIN sys.extended_properties AS p ON p.major_id = t.object_id AND p.minor_id = 0 AND p.name = N'MS_Description'
WHERE s.name = 'dw' AND t.name IN ('statement_line', 'statement_line_member', 'account_statement_line')
  AND (p.value IS NULL OR CAST(p.value AS nvarchar(4000)) NOT LIKE 'AUTHORED%')
UNION ALL
SELECT 'statement table with a decimal, float, real or money column', t.name + '.' + c.name
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.columns AS c ON c.object_id = t.object_id
JOIN sys.types AS y ON y.user_type_id = c.user_type_id
WHERE ((s.name = 'dw' AND t.name IN ('statement_line', 'statement_line_member', 'account_statement_line'))
    OR (s.name = 'authored' AND t.name IN ('statement_line', 'statement_account_rule'))
    OR (s.name = 'stg' AND t.name IN ('statement_line', 'statement_account_rule')))
  AND y.name IN ('decimal', 'numeric', 'float', 'real', 'money', 'smallmoney')
UNION ALL
SELECT 'the Unknown account is not mapped exactly once', 'UNK'
WHERE (SELECT COUNT(*) FROM dw.account_statement_line AS m JOIN dw.dim_account AS a ON a.account_key = m.account_key
       WHERE a.economic_category_code = 'UNK') <> 1;
