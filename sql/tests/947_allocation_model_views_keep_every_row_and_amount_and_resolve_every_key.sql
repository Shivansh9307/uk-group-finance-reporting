-- test: the views the model reads for the allocation keep every row of their base tables and the sum of every amount and weight column, every key resolves (the department in dw.v_model_department, the pool in the pool view, the financial year in dw.v_model_fiscal_year, the rule in the rule view), a bridge row has no department that is the pool department, and the what-if view has the rows of the synthetic table
-- marker: localdata
-- requires: dw.v_model_allocation_rule, dw.v_model_allocation_pool, dw.v_model_allocation_bridge, dw.v_model_allocation_coverage, dw.v_model_whatif_setting, dw.fact_allocation, dw.allocation_pool, audit.allocation_year_summary, synthetic.whatif_parameter
SELECT v.what, 'rows or an amount differ' AS problem
FROM (VALUES
  ('rule rows', (SELECT COUNT_BIG(*) FROM dw.v_model_allocation_rule), (SELECT COUNT_BIG(*) FROM authored.allocation_rule)),
  ('pool rows', (SELECT COUNT_BIG(*) FROM dw.v_model_allocation_pool), (SELECT COUNT_BIG(*) FROM dw.allocation_pool)),
  ('pool amount', (SELECT SUM(pool_amount) FROM dw.v_model_allocation_pool), (SELECT SUM(pool_amount) FROM dw.allocation_pool)),
  ('bridge rows', (SELECT COUNT_BIG(*) FROM dw.v_model_allocation_bridge), (SELECT COUNT_BIG(*) FROM dw.fact_allocation)),
  ('pool allocated total', (SELECT SUM(allocated_total) FROM dw.v_model_allocation_pool), (SELECT SUM(allocated_amount) FROM dw.fact_allocation)),
  ('allocated amount',(SELECT SUM(allocated_amount) FROM dw.v_model_allocation_bridge), (SELECT SUM(allocated_amount) FROM dw.fact_allocation)),
  ('rounding adjustment', (SELECT SUM(rounding_adjustment) FROM dw.v_model_allocation_bridge), (SELECT SUM(rounding_adjustment) FROM dw.fact_allocation)),
  ('weight', (SELECT SUM(weight) FROM dw.v_model_allocation_bridge), (SELECT SUM(weight) FROM dw.fact_allocation)),
  ('paybill', (SELECT SUM(paybill_annualised) FROM dw.v_model_allocation_bridge), (SELECT SUM(paybill_annualised) FROM dw.fact_allocation)),
  ('full-time equivalent', (SELECT SUM(avg_fte) FROM dw.v_model_allocation_bridge), (SELECT SUM(avg_fte) FROM dw.fact_allocation)),
  ('coverage rows', (SELECT COUNT_BIG(*) FROM dw.v_model_allocation_coverage), (SELECT COUNT_BIG(*) FROM audit.allocation_year_summary)),
  ('what-if rows', (SELECT COUNT_BIG(*) FROM dw.v_model_whatif_setting), (SELECT COUNT_BIG(*) FROM synthetic.whatif_parameter))
) AS v (what, a, b) WHERE v.a <> v.b
UNION ALL
SELECT 'bridge department', CONCAT('a row has a department that is not in dw.v_model_department: ', b.department_key)
FROM dw.v_model_allocation_bridge AS b
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_department AS d WHERE d.department_key = b.department_key) GROUP BY b.department_key
UNION ALL
SELECT 'bridge pool', 'a row has a pool that is not in the pool view'
FROM dw.v_model_allocation_bridge AS b
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_allocation_pool AS p WHERE p.pool_key = b.pool_key) GROUP BY b.pool_key
UNION ALL
SELECT 'bridge year and rule', 'a bridge row names another year or rule than its pool'
FROM dw.v_model_allocation_bridge AS b JOIN dw.v_model_allocation_pool AS p ON p.pool_key = b.pool_key
WHERE p.financial_year <> b.financial_year OR p.rule_id <> b.rule_id
UNION ALL
SELECT 'financial year', CONCAT('a pool has a financial year that is not in dw.v_model_fiscal_year: ', p.financial_year)
FROM dw.v_model_allocation_pool AS p
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_fiscal_year AS y WHERE y.financial_year = p.financial_year)
UNION ALL
SELECT 'coverage year', CONCAT('a coverage row has a financial year that is not in dw.v_model_fiscal_year: ', c.financial_year)
FROM dw.v_model_allocation_coverage AS c
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_fiscal_year AS y WHERE y.financial_year = c.financial_year)
UNION ALL
SELECT 'pool rule', 'a pool has a rule that is not in the rule view'
FROM dw.v_model_allocation_pool AS p
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_allocation_rule AS r WHERE r.rule_id = p.rule_id) GROUP BY p.rule_id
UNION ALL
SELECT 'pool department', 'a pool department is not in dw.v_model_department'
FROM dw.v_model_allocation_pool AS p
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_department AS d WHERE d.department_key = p.department_key) GROUP BY p.department_key;
