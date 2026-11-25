-- test: the views the model reads for the allocation keep every row of their base tables and the sum of every amount and weight column, the pool and the year's allocated total stored on each bridge row are the year's pool and the sum of its allocated amounts, every key resolves (the department in dw.v_model_department, the financial year in dw.v_model_fiscal_year, the rule in the rule view), and the what-if view has the rows of the synthetic table
-- marker: localdata
-- requires: dw.v_model_allocation_rule, dw.v_model_allocation_bridge, dw.v_model_allocation_coverage, dw.v_model_whatif_setting, dw.fact_allocation, dw.allocation_pool, audit.allocation_year_summary, synthetic.whatif_parameter
SELECT v.what, 'rows or an amount differ' AS problem
FROM (VALUES
  ('rule rows', (SELECT COUNT_BIG(*) FROM dw.v_model_allocation_rule), (SELECT COUNT_BIG(*) FROM authored.allocation_rule)),
  ('bridge rows', (SELECT COUNT_BIG(*) FROM dw.v_model_allocation_bridge), (SELECT COUNT_BIG(*) FROM dw.fact_allocation)),
  ('allocated amount', (SELECT SUM(allocated_amount) FROM dw.v_model_allocation_bridge), (SELECT SUM(allocated_amount) FROM dw.fact_allocation)),
  ('rounding adjustment', (SELECT SUM(rounding_adjustment) FROM dw.v_model_allocation_bridge), (SELECT SUM(rounding_adjustment) FROM dw.fact_allocation)),
  ('weight', (SELECT SUM(weight) FROM dw.v_model_allocation_bridge), (SELECT SUM(weight) FROM dw.fact_allocation)),
  ('paybill', (SELECT SUM(paybill_annualised) FROM dw.v_model_allocation_bridge), (SELECT SUM(paybill_annualised) FROM dw.fact_allocation)),
  ('full-time equivalent', (SELECT SUM(avg_fte) FROM dw.v_model_allocation_bridge), (SELECT SUM(avg_fte) FROM dw.fact_allocation)),
  ('coverage rows', (SELECT COUNT_BIG(*) FROM dw.v_model_allocation_coverage), (SELECT COUNT_BIG(*) FROM audit.allocation_year_summary)),
  ('what-if rows', (SELECT COUNT_BIG(*) FROM dw.v_model_whatif_setting), (SELECT COUNT_BIG(*) FROM synthetic.whatif_parameter))
) AS v (what, a, b) WHERE v.a <> v.b
UNION ALL
SELECT 'pool on a bridge row', CONCAT('a row of ', b.financial_year, ' carries a pool or an allocated total that is not the year''s')
FROM dw.v_model_allocation_bridge AS b
JOIN dw.allocation_pool AS p ON p.rule_id = b.rule_id AND p.financial_year = b.financial_year
WHERE b.pool_amount <> p.pool_amount
   OR b.allocated_total <> (SELECT SUM(f.allocated_amount) FROM dw.fact_allocation AS f WHERE f.rule_id = b.rule_id AND f.financial_year = b.financial_year)
GROUP BY b.financial_year
UNION ALL
SELECT 'bridge row without a pool', 'a bridge row has no pool in dw.allocation_pool'
FROM dw.v_model_allocation_bridge AS b
WHERE NOT EXISTS (SELECT 1 FROM dw.allocation_pool AS p WHERE p.rule_id = b.rule_id AND p.financial_year = b.financial_year)
UNION ALL
SELECT 'bridge department', CONCAT('a row has a department that is not in dw.v_model_department: ', b.department_key)
FROM dw.v_model_allocation_bridge AS b
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_department AS d WHERE d.department_key = b.department_key) GROUP BY b.department_key
UNION ALL
SELECT 'bridge financial year', CONCAT('a row has a financial year that is not in dw.v_model_fiscal_year: ', b.financial_year)
FROM dw.v_model_allocation_bridge AS b
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_fiscal_year AS y WHERE y.financial_year = b.financial_year) GROUP BY b.financial_year
UNION ALL
SELECT 'coverage year', CONCAT('a coverage row has a financial year that is not in dw.v_model_fiscal_year: ', c.financial_year)
FROM dw.v_model_allocation_coverage AS c
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_fiscal_year AS y WHERE y.financial_year = c.financial_year)
UNION ALL
SELECT 'bridge rule', 'a row has a rule that is not in the rule view'
FROM dw.v_model_allocation_bridge AS b
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_allocation_rule AS r WHERE r.rule_id = b.rule_id) GROUP BY b.rule_id;
