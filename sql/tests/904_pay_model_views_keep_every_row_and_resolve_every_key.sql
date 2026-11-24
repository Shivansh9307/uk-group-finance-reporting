-- test: the pay model views keep the rows of what they select (the bridge view the rows of dw.v_pay_bridge_row, the organisation view one row for each of the 89 organisations of dw.workforce_month, the coverage view the 1,353 rows of audit.workforce_mapping_coverage with the same paybill, the step view five rows), and every key of the bridge and coverage views resolves: the department in dw.v_model_department, the organisation in the organisation view, the fiscal period in dw.dim_period
-- marker: localdata
-- requires: dw.v_model_pay_bridge, audit.workforce_mapping_coverage
SELECT v.what, 'rows differ' AS problem
FROM (VALUES
  ('bridge rows', (SELECT COUNT_BIG(*) FROM dw.v_model_pay_bridge), (SELECT COUNT_BIG(*) FROM dw.v_pay_bridge_row)),
  ('organisations', (SELECT COUNT_BIG(*) FROM dw.v_model_pay_organisation), (SELECT COUNT_BIG(DISTINCT durable_key) FROM dw.workforce_month)),
  ('organisations 89', (SELECT COUNT_BIG(*) FROM dw.v_model_pay_organisation), CAST(89 AS bigint)),
  ('coverage rows', (SELECT COUNT_BIG(*) FROM dw.v_model_pay_coverage), (SELECT COUNT_BIG(*) FROM audit.workforce_mapping_coverage)),
  ('coverage 1353', (SELECT COUNT_BIG(*) FROM dw.v_model_pay_coverage), CAST(1353 AS bigint)),
  ('steps', (SELECT COUNT_BIG(*) FROM dw.v_model_pay_bridge_step), CAST(5 AS bigint))
) AS v (what, a, b) WHERE v.a <> v.b
UNION ALL
SELECT 'coverage paybill', 'the paybill of the coverage view is not that of the audit table'
FROM (SELECT (SELECT SUM(paybill_total) FROM dw.v_model_pay_coverage) AS a,
             (SELECT SUM(CAST(paybill_total AS decimal(19, 4))) FROM audit.workforce_mapping_coverage) AS b) AS t WHERE t.a <> t.b
UNION ALL
SELECT 'department key', 'a bridge row has a department that is not in dw.v_model_department'
FROM dw.v_model_pay_bridge AS b WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_department AS d WHERE d.department_key = b.department_key) GROUP BY b.department_key
UNION ALL
SELECT 'organisation key', 'a bridge row has an organisation that is not in the organisation view'
FROM dw.v_model_pay_bridge AS b WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_pay_organisation AS o WHERE o.durable_key = b.durable_key) GROUP BY b.durable_key
UNION ALL
SELECT 'period key', 'a bridge row or a coverage row has a fiscal period that is not in dw.dim_period'
FROM (SELECT period_key FROM dw.v_model_pay_bridge UNION SELECT period_key FROM dw.v_model_pay_coverage) AS k
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_period AS p WHERE p.period_key = k.period_key);
