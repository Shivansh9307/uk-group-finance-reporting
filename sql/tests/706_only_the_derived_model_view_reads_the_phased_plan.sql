-- test: of every view and procedure, only dw.v_model_fact_plan_phased reads the phased plan, nothing reads the phasing profile, and the phased view carries the derived flag and the method on every row
SELECT 'a view or procedure other than the model view reads the phased plan' AS problem,
       OBJECT_SCHEMA_NAME(d.referencing_id) + '.' + OBJECT_NAME(d.referencing_id) AS detail
FROM sys.sql_expression_dependencies AS d
WHERE d.referenced_id = OBJECT_ID('dw.fact_plan_phased')
  AND d.referencing_id <> OBJECT_ID('dw.v_model_fact_plan_phased')
UNION ALL
SELECT 'a view or procedure reads the phasing profile',
       OBJECT_SCHEMA_NAME(d.referencing_id) + '.' + OBJECT_NAME(d.referencing_id)
FROM sys.sql_expression_dependencies AS d
WHERE d.referenced_id = OBJECT_ID('dw.plan_phasing_profile')
UNION ALL
SELECT 'the phased view does not read the phased plan', 'dw.v_model_fact_plan_phased'
WHERE NOT EXISTS (SELECT 1 FROM sys.sql_expression_dependencies AS d
                  WHERE d.referencing_id = OBJECT_ID('dw.v_model_fact_plan_phased') AND d.referenced_id = OBJECT_ID('dw.fact_plan_phased'))
UNION ALL
SELECT 'a phased row is not flagged derived or has no method', CAST(x.plan_fact_key AS nvarchar(20))
FROM dw.v_model_fact_plan_phased AS x WHERE x.is_derived <> 1 OR x.method IS NULL OR LEN(x.method) = 0
;
