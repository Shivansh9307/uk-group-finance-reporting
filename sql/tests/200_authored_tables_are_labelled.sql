-- test: every table in schema authored says in its description that it is authored data
SELECT s.name AS schema_name, t.name AS table_name, CAST(p.value AS nvarchar(400)) AS description
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
LEFT JOIN sys.extended_properties AS p ON p.major_id = t.object_id AND p.minor_id = 0 AND p.name = N'MS_Description'
WHERE s.name = 'authored'
  AND (p.value IS NULL OR CAST(p.value AS nvarchar(4000)) NOT LIKE 'AUTHORED%');
