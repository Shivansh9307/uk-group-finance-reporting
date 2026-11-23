-- test: of every view, procedure and table in the warehouse only dw.v_model_user_department and dw.v_model_user_plan_group read the synthetic table, nothing reads those two views, no foreign key points at the synthetic table, and the synthetic and scale schemas hold exactly the one table, with no numeric column
SELECT 'an object other than the two role views reads the synthetic table' AS problem,
       OBJECT_SCHEMA_NAME(d.referencing_id) + '.' + OBJECT_NAME(d.referencing_id) AS detail
FROM sys.sql_expression_dependencies AS d
WHERE d.referenced_id = OBJECT_ID('synthetic.user_department')
  AND d.referencing_id NOT IN (OBJECT_ID('dw.v_model_user_department'), OBJECT_ID('dw.v_model_user_plan_group'))
  AND d.referencing_id NOT IN (SELECT object_id FROM sys.check_constraints WHERE parent_object_id = OBJECT_ID('synthetic.user_department'))
UNION ALL
SELECT 'an object reads a role view', OBJECT_SCHEMA_NAME(d.referencing_id) + '.' + OBJECT_NAME(d.referencing_id)
FROM sys.sql_expression_dependencies AS d
WHERE d.referenced_id IN (OBJECT_ID('dw.v_model_user_department'), OBJECT_ID('dw.v_model_user_plan_group'))
UNION ALL
SELECT 'a role view does not read the synthetic table', v.name
FROM sys.views AS v
WHERE v.object_id IN (OBJECT_ID('dw.v_model_user_department'), OBJECT_ID('dw.v_model_user_plan_group'))
  AND NOT EXISTS (SELECT 1 FROM sys.sql_expression_dependencies AS d
                  WHERE d.referencing_id = v.object_id AND d.referenced_id = OBJECT_ID('synthetic.user_department'))
UNION ALL
SELECT 'a foreign key points at the synthetic table', OBJECT_NAME(fk.parent_object_id)
FROM sys.foreign_keys AS fk WHERE fk.referenced_object_id = OBJECT_ID('synthetic.user_department')
UNION ALL
SELECT 'a table in the synthetic or scale schema other than user_department', SCHEMA_NAME(t.schema_id) + '.' + t.name
FROM sys.tables AS t
WHERE SCHEMA_NAME(t.schema_id) IN ('synthetic', 'scale') AND t.object_id <> OBJECT_ID('synthetic.user_department')
UNION ALL
SELECT 'a synthetic column holds a number', c.name
FROM sys.columns AS c JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('synthetic.user_department')
  AND ty.name IN ('decimal', 'numeric', 'float', 'real', 'money', 'smallmoney', 'bigint', 'smallint', 'tinyint')
UNION ALL
SELECT 'a view of a fact has a column that names a user', OBJECT_NAME(c.object_id)
FROM sys.columns AS c JOIN sys.views AS v ON v.object_id = c.object_id
WHERE SCHEMA_NAME(v.schema_id) = 'dw' AND v.name LIKE 'v[_]model[_]fact%' AND c.name LIKE '%user%';
