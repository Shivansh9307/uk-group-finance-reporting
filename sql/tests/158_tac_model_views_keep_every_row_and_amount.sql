-- test: each TAC model view keeps the rows of its base table (the cash-flow line view adds the member 0), the fact view keeps every amount and the sum of its restatement column equals the net difference of audit.tac_prior_year_summary by year and statement, every key of the fact views resolves in its dimension view (no blank member in the model), every provider has a department key, and the department key is one that dw.dim_department has
-- marker: localdata
-- requires: dw.v_model_tac_fact, dw.v_model_tac_provider, audit.tac_prior_year_summary
SELECT v.view_name AS what, 'rows or amount differ from the base table' AS problem
FROM (VALUES
    ('dw.v_model_tac_fact rows', (SELECT COUNT_BIG(*) FROM dw.v_model_tac_fact), (SELECT COUNT_BIG(*) FROM dw.tac_fact)),
    ('dw.v_model_tac_provider rows', (SELECT COUNT_BIG(*) FROM dw.v_model_tac_provider), (SELECT COUNT_BIG(*) FROM dw.tac_provider)),
    ('dw.v_model_tac_line rows', (SELECT COUNT_BIG(*) FROM dw.v_model_tac_line), (SELECT COUNT_BIG(*) FROM dw.tac_statutory_line)),
    ('dw.v_model_tac_cash_flow_line rows', (SELECT COUNT_BIG(*) FROM dw.v_model_tac_cash_flow_line), (SELECT COUNT_BIG(*) + 1 FROM dw.tac_cash_flow_line)),
    ('dw.v_model_tac_cash_flow_derived rows', (SELECT COUNT_BIG(*) FROM dw.v_model_tac_cash_flow_derived), (SELECT COUNT_BIG(*) FROM dw.tac_cash_flow_derived)),
    ('dw.v_model_tac_consolidated rows', (SELECT COUNT_BIG(*) FROM dw.v_model_tac_consolidated), (SELECT COUNT_BIG(*) FROM dw.tac_consolidated_control)),
    ('dw.v_model_tac_control_line rows', (SELECT COUNT_BIG(*) FROM dw.v_model_tac_control_line), (SELECT COUNT_BIG(*) FROM dw.tac_control_line)),
    ('dw.v_model_tac_control_member rows', (SELECT COUNT_BIG(*) FROM dw.v_model_tac_control_member), (SELECT COUNT_BIG(*) FROM dw.tac_control_member)),
    ('dw.v_model_tac_fact amount', (SELECT CAST(SUM(value) AS decimal(38,4)) FROM dw.v_model_tac_fact), (SELECT CAST(SUM(value) AS decimal(38,4)) FROM dw.tac_fact)),
    ('dw.v_model_tac_cash_flow_derived amount', (SELECT CAST(SUM(amount) AS decimal(38,4)) FROM dw.v_model_tac_cash_flow_derived), (SELECT CAST(SUM(amount) AS decimal(38,4)) FROM dw.tac_cash_flow_derived)),
    ('dw.v_model_tac_consolidated amount', (SELECT CAST(SUM(amount) AS decimal(38,4)) FROM dw.v_model_tac_consolidated), (SELECT CAST(SUM(amount) AS decimal(38,4)) FROM dw.tac_consolidated_control))
) AS v(view_name, got, want)
WHERE v.got <> v.want
UNION ALL
SELECT s.release + ' ' + s.statement, 'restatement column differs from the net difference of the prior-year audit'
FROM audit.tac_prior_year_summary AS s
LEFT JOIN (SELECT f.financial_year, l.statement, SUM(f.restatement_amount) AS restated
           FROM dw.v_model_tac_fact AS f JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key
           GROUP BY f.financial_year, l.statement) AS q ON q.financial_year = s.release AND q.statement = s.statement
WHERE ABS(ISNULL(q.restated, 0) - s.net_difference) >= 0.0001
UNION ALL
SELECT 'dw.v_model_tac_fact', 'the restatement column is filled on a current-year row, or on a row that does not differ by 1 or more'
WHERE EXISTS (SELECT 1 FROM dw.v_model_tac_fact WHERE (period_column = 'CY' AND restatement_amount IS NOT NULL) OR ABS(restatement_amount) < 1)
UNION ALL
SELECT 'dw.v_model_tac_fact', 'the number of restated values is not the 1,406 of audit.tac_prior_year_difference'
WHERE (SELECT COUNT(*) FROM dw.v_model_tac_fact WHERE restatement_amount IS NOT NULL) <> (SELECT COUNT(*) FROM audit.tac_prior_year_difference)
UNION ALL
SELECT 'dw.v_model_tac_fact', 'a fact row whose provider, line or year has no member'
WHERE EXISTS (SELECT 1 FROM dw.v_model_tac_fact AS f
              WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_tac_provider AS p WHERE p.provider_key = f.provider_key)
                 OR NOT EXISTS (SELECT 1 FROM dw.v_model_tac_line AS l WHERE l.line_key = f.line_key)
                 OR NOT EXISTS (SELECT 1 FROM dw.v_model_fiscal_year AS y WHERE y.financial_year = f.financial_year))
UNION ALL
SELECT 'dw.v_model_tac_cash_flow_derived', 'a derived row whose provider, line or year has no member'
WHERE EXISTS (SELECT 1 FROM dw.v_model_tac_cash_flow_derived AS f
              WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_tac_provider AS p WHERE p.provider_key = f.provider_key)
                 OR NOT EXISTS (SELECT 1 FROM dw.v_model_tac_cash_flow_line AS l WHERE l.cash_flow_line_key = f.cash_flow_line_key)
                 OR NOT EXISTS (SELECT 1 FROM dw.v_model_fiscal_year AS y WHERE y.financial_year = f.financial_year))
UNION ALL
SELECT 'dw.v_model_tac_line', 'a statement line whose comparison key has no member'
WHERE EXISTS (SELECT 1 FROM dw.v_model_tac_line AS l WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_tac_cash_flow_line AS c WHERE c.cash_flow_line_key = l.cash_flow_line_key))
UNION ALL
SELECT 'dw.v_model_tac_consolidated', 'a printed line whose control line or year has no member'
WHERE EXISTS (SELECT 1 FROM dw.v_model_tac_consolidated AS c
              WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_tac_control_line AS l WHERE l.control_line_key = c.control_line_key)
                 OR NOT EXISTS (SELECT 1 FROM dw.v_model_fiscal_year AS y WHERE y.financial_year = c.financial_year))
UNION ALL
SELECT 'dw.v_model_tac_provider', 'a provider whose department key is not a department of the current structure'
WHERE EXISTS (SELECT 1 FROM dw.v_model_tac_provider AS p WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_department AS d WHERE d.department_key = p.department_key));
