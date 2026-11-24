-- test: nothing authored reaches a TAC total: the authored TAC tables hold no numeric column, the fact is built from stg.tac_value only and its total equals the staged total less the unmapped rows, the authored columns of the dimensions are labelled in the table description, and the amount is DECIMAL(19,4)
-- marker: localdata
SELECT s.name + '.' + t.name AS object_name, c.name AS detail, 'authored TAC table has a numeric column' AS problem
FROM sys.columns AS c
JOIN sys.tables AS t ON t.object_id = c.object_id
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE s.name = 'authored' AND t.name LIKE 'tac[_]%' AND ty.name NOT IN ('nvarchar', 'int')
UNION ALL
SELECT 'dw.tac_fact', CAST((SELECT SUM(value) FROM stg.tac_value) AS varchar(40)), 'fact total differs from the staged total less unmapped'
WHERE (SELECT SUM(value) FROM stg.tac_value) <> (SELECT SUM(value) FROM dw.tac_fact) + ISNULL((SELECT SUM(value) FROM quarantine.tac_unmapped_row), 0)
UNION ALL
SELECT 'dw.tac_fact.value', ty.name + '(' + CAST(c.precision AS varchar(5)) + ',' + CAST(c.scale AS varchar(5)) + ')', 'amount is not DECIMAL(19,4)'
FROM sys.columns AS c
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('dw.tac_fact') AND c.name = 'value' AND NOT (ty.name = 'decimal' AND c.precision = 19 AND c.scale = 4)
UNION ALL
SELECT 'dw.' + t.name, NULL, 'description does not say what is authored'
FROM sys.tables AS t
WHERE t.schema_id = SCHEMA_ID('dw') AND t.name IN ('tac_provider', 'tac_statutory_line')
  AND NOT EXISTS (SELECT 1 FROM sys.extended_properties AS e
                  WHERE e.major_id = t.object_id AND e.minor_id = 0 AND e.name = 'MS_Description' AND CAST(e.value AS nvarchar(max)) LIKE '%authored%')
UNION ALL
SELECT 'authored.' + t.name, NULL, 'authored table without a description'
FROM sys.tables AS t
WHERE t.schema_id = SCHEMA_ID('authored') AND t.name LIKE 'tac[_]%'
  AND NOT EXISTS (SELECT 1 FROM sys.extended_properties AS e
                  WHERE e.major_id = t.object_id AND e.minor_id = 0 AND e.name = 'MS_Description' AND CAST(e.value AS nvarchar(max)) LIKE '%AUTHORED%');
