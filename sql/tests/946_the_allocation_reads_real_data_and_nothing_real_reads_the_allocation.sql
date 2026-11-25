-- test: the allocation reaches no real total. Only the model's allocation views and the audit summary read the allocation tables, nothing reads the model's allocation views, no foreign key points at them other than the one from the fact to the pool, the allocation objects read real data and the authored rule only (the objects on a short list), none of the real facts or the views of a real fact has an allocation column
-- marker: localdata
-- requires: dw.fact_allocation, dw.allocation_pool, audit.allocation_participation, audit.allocation_year_summary, dw.v_model_allocation_bridge
SELECT 'an object other than the allocation views and summary reads an allocation table' AS problem,
       CONCAT(OBJECT_SCHEMA_NAME(d.referencing_id), '.', OBJECT_NAME(d.referencing_id), ' reads ', d.referenced_schema_name, '.', d.referenced_entity_name) AS detail
FROM sys.sql_expression_dependencies AS d
WHERE d.referenced_id IN (OBJECT_ID('dw.fact_allocation'), OBJECT_ID('dw.allocation_pool'), OBJECT_ID('audit.allocation_participation'), OBJECT_ID('audit.allocation_year_summary'), OBJECT_ID('authored.allocation_rule'))
  AND d.referencing_id NOT IN (OBJECT_ID('dw.v_model_allocation_rule'), OBJECT_ID('dw.v_model_allocation_pool'),
                               OBJECT_ID('dw.v_model_allocation_bridge'), OBJECT_ID('dw.v_model_allocation_coverage'))
  AND d.referencing_id NOT IN (SELECT object_id FROM sys.check_constraints)
  AND d.referencing_id NOT IN (SELECT object_id FROM sys.foreign_keys)
  AND OBJECT_NAME(d.referencing_id) NOT IN ('allocation_pool', 'allocation_participation', 'fact_allocation', 'allocation_year_summary')
UNION ALL
SELECT 'an object reads a model allocation view', CONCAT(OBJECT_SCHEMA_NAME(d.referencing_id), '.', OBJECT_NAME(d.referencing_id))
FROM sys.sql_expression_dependencies AS d
WHERE d.referenced_id IN (OBJECT_ID('dw.v_model_allocation_rule'), OBJECT_ID('dw.v_model_allocation_pool'),
                          OBJECT_ID('dw.v_model_allocation_bridge'), OBJECT_ID('dw.v_model_allocation_coverage'))
UNION ALL
SELECT 'a foreign key points at an allocation table from outside the allocation', OBJECT_NAME(fk.parent_object_id)
FROM sys.foreign_keys AS fk
WHERE fk.referenced_object_id IN (OBJECT_ID('dw.fact_allocation'), OBJECT_ID('dw.allocation_pool'))
  AND OBJECT_NAME(fk.parent_object_id) <> 'fact_allocation'
UNION ALL
SELECT 'the allocation reads an object that is not on the list', CONCAT(OBJECT_SCHEMA_NAME(d.referencing_id), '.', OBJECT_NAME(d.referencing_id), ' reads ', d.referenced_schema_name, '.', d.referenced_entity_name)
FROM sys.sql_expression_dependencies AS d
WHERE d.referencing_id IN (OBJECT_ID('dw.v_model_allocation_rule'), OBJECT_ID('dw.v_model_allocation_pool'), OBJECT_ID('dw.v_model_allocation_bridge'), OBJECT_ID('dw.v_model_allocation_coverage'))
  AND CONCAT(d.referenced_schema_name, '.', d.referenced_entity_name) NOT IN
      ('dw.fact_allocation', 'dw.allocation_pool', 'audit.allocation_year_summary', 'authored.allocation_rule')
UNION ALL
SELECT 'a real fact view or a real fact has an allocation column', OBJECT_NAME(c.object_id)
FROM sys.columns AS c
WHERE c.object_id IN (SELECT object_id FROM sys.views WHERE SCHEMA_NAME(schema_id) = 'dw' AND name LIKE 'v[_]model[_]fact%'
                      UNION ALL SELECT OBJECT_ID('dw.fact_outturn') UNION ALL SELECT OBJECT_ID('dw.fact_plan') UNION ALL SELECT OBJECT_ID('dw.fact_outturn_annual'))
  AND (c.name LIKE '%allocat%' OR c.name LIKE '%pool%');
