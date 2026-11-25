-- test: the allocation rule is one authored row that says so (data class and table description), its pool department and control budget detail exist in the dimensions, its years are closed years of the outturn, every year of the rule has exactly one pool and there is no pool outside the rule's years, and the pool department takes no part in the weights (the workforce source does not hold it)
-- marker: localdata
-- requires: authored.allocation_rule, dw.allocation_pool, dw.fact_allocation, dw.dim_department, dw.dim_control_budget, dw.dim_period
SELECT 'the rule table does not hold exactly one rule' AS problem, CAST(COUNT(*) AS varchar(10)) AS detail
FROM authored.allocation_rule HAVING COUNT(*) <> 1
UNION ALL
SELECT 'a rule is not authored', rule_id FROM authored.allocation_rule WHERE data_class <> 'authored'
UNION ALL
SELECT 'description does not begin AUTHORED', 'authored.allocation_rule'
WHERE NOT EXISTS (SELECT 1 FROM sys.extended_properties AS e
                  WHERE e.class = 1 AND e.major_id = OBJECT_ID('authored.allocation_rule') AND e.minor_id = 0
                    AND e.name = 'MS_Description' AND CAST(e.value AS nvarchar(4000)) LIKE 'AUTHORED%')
UNION ALL
SELECT 'the pool department is not exactly one current department', r.rule_id
FROM authored.allocation_rule AS r
WHERE (SELECT COUNT(*) FROM dw.dim_department AS d WHERE d.department_number = r.pool_department_number AND d.is_current = 1) <> 1
UNION ALL
SELECT 'the pool control budget detail does not exist', r.rule_id
FROM authored.allocation_rule AS r
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_control_budget AS cb WHERE cb.control_budget_detail_code = r.pool_control_budget_detail_code)
UNION ALL
SELECT 'the rule runs into a year that is not closed (the latest in-year release must be a later year)', r.rule_id
FROM authored.allocation_rule AS r
WHERE r.last_financial_year >= (SELECT MAX(financial_year) FROM dw.dim_release WHERE is_latest_release = 1)
UNION ALL
SELECT 'a financial year of the rule has no pool, or more than one', y.financial_year
FROM authored.allocation_rule AS r
CROSS APPLY (SELECT DISTINCT p.financial_year FROM dw.dim_period AS p
             WHERE p.financial_year BETWEEN r.first_financial_year AND r.last_financial_year) AS y
WHERE (SELECT COUNT(*) FROM dw.allocation_pool AS pl WHERE pl.rule_id = r.rule_id AND pl.financial_year = y.financial_year) <> 1
UNION ALL
SELECT 'a pool outside the years of the rule', pl.financial_year
FROM dw.allocation_pool AS pl JOIN authored.allocation_rule AS r ON r.rule_id = pl.rule_id
WHERE pl.financial_year NOT BETWEEN r.first_financial_year AND r.last_financial_year
UNION ALL
SELECT 'the pool department has an allocation row', CAST(f.financial_year AS varchar(10))
FROM dw.fact_allocation AS f JOIN dw.allocation_pool AS pl ON pl.pool_key = f.pool_key
WHERE f.department_key = pl.pool_department_key;
