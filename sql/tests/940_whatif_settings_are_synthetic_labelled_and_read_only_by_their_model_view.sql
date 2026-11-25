-- test: the what-if settings are synthetic and labelled so (table description begins SYNTHETIC, every row says synthetic), there is exactly one default setting, nothing but dw.v_model_whatif_setting reads the table, nothing reads that view, no foreign key points at the table, its numeric columns are the two percentages and no amount, the base pay award is the 3.4 per cent of the ONS series it names, and no view of a real fact has a what-if column
-- requires: synthetic.whatif_parameter, dw.v_model_whatif_setting
SELECT 'description does not begin SYNTHETIC' AS problem, 'synthetic.whatif_parameter' AS detail
WHERE NOT EXISTS (SELECT 1 FROM sys.extended_properties AS e
                  WHERE e.class = 1 AND e.major_id = OBJECT_ID('synthetic.whatif_parameter') AND e.minor_id = 0
                    AND e.name = 'MS_Description' AND CAST(e.value AS nvarchar(4000)) LIKE 'SYNTHETIC%')
UNION ALL
SELECT 'a row is not synthetic', CAST(setting_key AS varchar(10)) FROM synthetic.whatif_parameter WHERE data_class <> 'synthetic'
UNION ALL
SELECT 'there is not exactly one default setting', CAST(COUNT(*) AS varchar(10)) FROM synthetic.whatif_parameter WHERE is_default = 1 HAVING COUNT(*) <> 1
UNION ALL
SELECT 'a setting is described as ONS but is not the base rate', setting_name
FROM synthetic.whatif_parameter WHERE pay_award_basis LIKE 'ONS%' AND pay_award_pct <> 3.4
UNION ALL
SELECT 'an object other than the model view reads the table', OBJECT_SCHEMA_NAME(d.referencing_id) + '.' + OBJECT_NAME(d.referencing_id)
FROM sys.sql_expression_dependencies AS d
WHERE d.referenced_id = OBJECT_ID('synthetic.whatif_parameter')
  AND d.referencing_id <> OBJECT_ID('dw.v_model_whatif_setting')
  AND d.referencing_id NOT IN (SELECT object_id FROM sys.check_constraints WHERE parent_object_id = OBJECT_ID('synthetic.whatif_parameter'))
UNION ALL
SELECT 'an object reads the what-if view', OBJECT_SCHEMA_NAME(d.referencing_id) + '.' + OBJECT_NAME(d.referencing_id)
FROM sys.sql_expression_dependencies AS d WHERE d.referenced_id = OBJECT_ID('dw.v_model_whatif_setting')
UNION ALL
SELECT 'a foreign key points at the table', OBJECT_NAME(fk.parent_object_id)
FROM sys.foreign_keys AS fk WHERE fk.referenced_object_id = OBJECT_ID('synthetic.whatif_parameter')
UNION ALL
SELECT 'a numeric column other than the two percentages', c.name
FROM sys.columns AS c JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('synthetic.whatif_parameter')
  AND ty.name IN ('decimal', 'numeric', 'float', 'real', 'money', 'smallmoney', 'bigint', 'smallint', 'tinyint')
  AND c.name NOT IN ('pay_award_pct', 'headcount_change_pct')
UNION ALL
SELECT 'a column of the what-if table is named like an amount', c.name
FROM sys.columns AS c
WHERE c.object_id = OBJECT_ID('synthetic.whatif_parameter') AND (c.name LIKE '%amount%' OR c.name LIKE '%gbp%' OR c.name LIKE '%value%')
UNION ALL
SELECT 'a view of a real fact has a what-if column', OBJECT_NAME(c.object_id)
FROM sys.columns AS c JOIN sys.views AS v ON v.object_id = c.object_id
WHERE SCHEMA_NAME(v.schema_id) = 'dw' AND v.name LIKE 'v[_]model[_]fact%' AND (c.name LIKE '%whatif%' OR c.name LIKE '%pay_award%' OR c.name LIKE '%headcount_change%');
