-- test: no FLOAT or REAL column exists anywhere, and the staged amount is DECIMAL(19,4)

SELECT s.name AS schema_name, t.name AS table_name, c.name AS column_name, ty.name AS type_name, 'float column' AS problem
FROM sys.columns AS c
JOIN sys.tables AS t ON t.object_id = c.object_id
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE ty.name IN ('float', 'real')
UNION ALL
SELECT 'stg', 'inyear_snapshot', 'amount', ty.name + '(' + CAST(c.precision AS varchar(3)) + ',' + CAST(c.scale AS varchar(3)) + ')',
       'amount must be decimal(19,4)'
FROM sys.columns AS c
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'stg.inyear_snapshot') AND c.name = 'amount'
  AND NOT (ty.name = 'decimal' AND c.precision = 19 AND c.scale = 4);
