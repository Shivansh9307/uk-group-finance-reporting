-- test: the pay bridge views read the real workforce fact and nothing authored or synthetic for any amount: the objects they read are on a short list (the fact, the organisation and department dimensions, the arithmetic audit, the raw file list and the row classes that only flag a cell, the coverage audit), and the current paybill of the bridge rows adds back to the paybill of the valid cells (the derived columns add no amount)
-- marker: localdata
-- requires: dw.v_model_pay_bridge, dw.workforce_month
SELECT CONCAT(OBJECT_SCHEMA_NAME(d.referencing_id), '.', OBJECT_NAME(d.referencing_id)) AS what,
       CONCAT('reads ', d.referenced_schema_name, '.', d.referenced_entity_name, ', which is not on the list') AS problem
FROM sys.sql_expression_dependencies AS d
WHERE d.referencing_id IN (OBJECT_ID('dw.v_pay_cell'), OBJECT_ID('dw.v_pay_bridge_row'), OBJECT_ID('dw.v_model_pay_bridge'),
                           OBJECT_ID('dw.v_model_pay_organisation'), OBJECT_ID('dw.v_model_pay_coverage'),
                           OBJECT_ID('dw.v_model_pay_bridge_step'))
  AND d.referenced_id IS NOT NULL
  AND CONCAT(d.referenced_schema_name, '.', d.referenced_entity_name) NOT IN
      ('dw.workforce_month', 'dw.dim_organisation', 'dw.dim_department', 'dw.department_reported_number',
       'audit.workforce_row_arithmetic', 'raw.workforce_file', 'stg.workforce_row_class', 'audit.workforce_mapping_coverage',
       'dw.v_pay_cell', 'dw.v_pay_bridge_row', 'dw.v_model_pay_bridge')
UNION ALL
SELECT 'cells', 'the current paybill of the bridge rows does not add back to the paybill of the valid cells'
FROM (SELECT (SELECT SUM(pay_cur) FROM dw.v_model_pay_bridge) AS bridge_current,
             (SELECT SUM(paybill) FROM dw.v_pay_cell WHERE cell_status = 'valid') AS valid_paybill) AS t
WHERE t.bridge_current <> t.valid_paybill;
