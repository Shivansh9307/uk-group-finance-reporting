-- test: nothing derived or authored reaches a real TAC total: the derived cash flow and the hand-keyed consolidated values are labelled DERIVED or AUTHORED in their descriptions; the derived table is read only by its model view and by the audit tables that compare it; the consolidated table only by its model view and the elimination-gap tables; the real fact view reads only dw.tac_fact; no foreign key points at the derived or authored tables from a fact; the real fact still has its 344,812 rows and no row of it is a derived or authored value
-- marker: localdata
-- requires: dw.tac_cash_flow_derived, dw.tac_consolidated_control
SELECT t.name AS object_name, 'description does not say DERIVED or AUTHORED' AS problem
FROM sys.tables AS t
WHERE t.schema_id = SCHEMA_ID('dw')
  AND t.name IN ('tac_cash_flow_derived', 'tac_cash_flow_line', 'tac_cash_flow_comparison', 'tac_control_line', 'tac_control_member', 'tac_consolidated_control')
  AND NOT EXISTS (SELECT 1 FROM sys.extended_properties AS e
                  WHERE e.class = 1 AND e.major_id = t.object_id AND e.minor_id = 0 AND e.name = N'MS_Description'
                    AND (CAST(e.value AS nvarchar(max)) LIKE N'DERIVED%' OR CAST(e.value AS nvarchar(max)) LIKE N'%AUTHORED%'))
UNION ALL
SELECT OBJECT_SCHEMA_NAME(d.referencing_id) + '.' + OBJECT_NAME(d.referencing_id), 'reads the derived cash flow but is not its model view or an audit table that compares it'
FROM sys.sql_expression_dependencies AS d
WHERE d.referenced_id = OBJECT_ID('dw.tac_cash_flow_derived')
  AND OBJECT_NAME(d.referencing_id) NOT IN ('v_model_tac_cash_flow_derived')
  AND OBJECT_SCHEMA_NAME(d.referencing_id) <> 'audit'
UNION ALL
SELECT OBJECT_SCHEMA_NAME(d.referencing_id) + '.' + OBJECT_NAME(d.referencing_id), 'reads the hand-keyed consolidated values but is not its model view or an elimination-gap table'
FROM sys.sql_expression_dependencies AS d
WHERE d.referenced_id = OBJECT_ID('dw.tac_consolidated_control')
  AND OBJECT_NAME(d.referencing_id) NOT IN ('v_model_tac_consolidated')
  AND OBJECT_SCHEMA_NAME(d.referencing_id) <> 'audit'
UNION ALL
SELECT 'dw.v_model_tac_fact', 'the real fact view reads another table than dw.tac_fact'
FROM sys.sql_expression_dependencies AS d
WHERE d.referencing_id = OBJECT_ID('dw.v_model_tac_fact') AND d.referenced_entity_name IS NOT NULL
  AND d.referenced_entity_name <> 'tac_fact'
GROUP BY d.referencing_id
UNION ALL
SELECT OBJECT_NAME(fk.parent_object_id), 'a foreign key points at a derived or authored table from outside its own family'
FROM sys.foreign_keys AS fk
WHERE fk.referenced_object_id IN (OBJECT_ID('dw.tac_cash_flow_derived'), OBJECT_ID('dw.tac_consolidated_control'))
UNION ALL
SELECT 'dw.tac_fact', 'the real fact has changed: expected 344,812 rows'
WHERE (SELECT COUNT_BIG(*) FROM dw.tac_fact) <> 344812
UNION ALL
SELECT 'dw.tac_fact', 'the real fact has a value that is not in the staged files (the total differs from the staged total less the unmapped rows)'
WHERE (SELECT SUM(value) FROM stg.tac_value) <> (SELECT SUM(value) FROM dw.tac_fact) + ISNULL((SELECT SUM(value) FROM quarantine.tac_unmapped_row), 0)
UNION ALL
SELECT 'dw.tac_fact', 'the real fact carries a column that is derived or authored'
FROM sys.columns AS c
WHERE c.object_id = OBJECT_ID('dw.tac_fact') AND (c.name LIKE '%derived%' OR c.name LIKE '%authored%' OR c.name LIKE '%consolidated%')
GROUP BY c.object_id
UNION ALL
SELECT s.name + '.' + t.name, 'a TAC table has a float or real column'
FROM sys.columns AS c
JOIN sys.tables AS t ON t.object_id = c.object_id
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE t.name LIKE 'tac[_]%' AND ty.name IN ('float', 'real')
UNION ALL
SELECT 'dw.' + c.name, 'a TAC amount that is not DECIMAL(19,4)'
FROM (SELECT 'tac_cash_flow_derived' AS name, 'amount' AS col UNION ALL SELECT 'tac_consolidated_control', 'amount') AS c
JOIN sys.columns AS sc ON sc.object_id = OBJECT_ID('dw.' + c.name) AND sc.name = c.col
JOIN sys.types AS ty ON ty.user_type_id = sc.user_type_id
WHERE NOT (ty.name = 'decimal' AND sc.precision = 19 AND sc.scale = 4);
