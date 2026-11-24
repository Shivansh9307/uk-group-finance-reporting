-- test: the accuracy view the model reads keeps every row of dw.forecast_accuracy and dw.forecast_pay_accuracy and the sum of every amount column of each, the method and return views have the four methods and the thirteen returns R0 to R12, every key of the accuracy view resolves (department in dw.v_model_department, financial year in dw.v_model_fiscal_year, method and return in their views), a cell is flagged common only where every method of its line is scored, the MAPE columns are set only where the outturn is at least GBP 100m, and the objects that make the accuracy read forecast returns, the workforce and the department maps and nothing authored or synthetic
-- marker: localdata
-- requires: dw.v_model_forecast_accuracy, dw.forecast_accuracy, dw.forecast_pay_accuracy, dw.forecast_fte_cost_input
SELECT v.what, 'rows or an amount differ' AS problem
FROM (VALUES
  ('rows', (SELECT COUNT_BIG(*) FROM dw.v_model_forecast_accuracy),
           (SELECT COUNT_BIG(*) FROM dw.forecast_accuracy) + (SELECT COUNT_BIG(*) FROM dw.forecast_pay_accuracy)),
  ('full-year abs error', (SELECT SUM(full_year_abs_error) FROM dw.v_model_forecast_accuracy),
           (SELECT SUM(full_year_abs_error) FROM dw.forecast_accuracy) + (SELECT SUM(full_year_abs_error) FROM dw.forecast_pay_accuracy)),
  ('full-year forecast', (SELECT SUM(full_year_forecast) FROM dw.v_model_forecast_accuracy),
           (SELECT SUM(full_year_forecast) FROM dw.forecast_accuracy) + (SELECT SUM(full_year_forecast) FROM dw.forecast_pay_accuracy)),
  ('full-year outturn', (SELECT SUM(full_year_outturn) FROM dw.v_model_forecast_accuracy),
           (SELECT SUM(full_year_outturn) FROM dw.forecast_accuracy) + (SELECT SUM(full_year_outturn) FROM dw.forecast_pay_accuracy)),
  ('forecast-month error', (SELECT SUM(fm_error) FROM dw.v_model_forecast_accuracy),
           (SELECT SUM(fm_error) FROM dw.forecast_accuracy) + (SELECT SUM(fm_error) FROM dw.forecast_pay_accuracy)),
  ('forecast-month abs error', (SELECT SUM(fm_abs_error) FROM dw.v_model_forecast_accuracy),
           (SELECT SUM(fm_abs_error) FROM dw.forecast_accuracy) + (SELECT SUM(fm_abs_error) FROM dw.forecast_pay_accuracy)),
  ('forecast-month abs outturn', (SELECT SUM(fm_abs_outturn) FROM dw.v_model_forecast_accuracy),
           (SELECT SUM(fm_abs_outturn) FROM dw.forecast_accuracy) + (SELECT SUM(fm_abs_outturn) FROM dw.forecast_pay_accuracy)),
  ('methods', (SELECT COUNT_BIG(*) FROM dw.v_model_forecast_method), CAST(4 AS bigint)),
  ('returns', (SELECT COUNT_BIG(*) FROM dw.v_model_forecast_return), CAST(13 AS bigint))
) AS v (what, a, b) WHERE v.a <> v.b
UNION ALL
SELECT 'department key', 'a row has a department that is not in dw.v_model_department'
FROM dw.v_model_forecast_accuracy AS a
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_department AS d WHERE d.department_key = a.department_key) GROUP BY a.department_key
UNION ALL
SELECT 'financial year', 'a row has a financial year that is not in dw.v_model_fiscal_year'
FROM dw.v_model_forecast_accuracy AS a
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_fiscal_year AS y WHERE y.financial_year = a.financial_year) GROUP BY a.financial_year
UNION ALL
SELECT 'method or return', 'a row has a method or a return that is not in its view'
FROM dw.v_model_forecast_accuracy AS a
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_forecast_method AS m WHERE m.method = a.method)
   OR NOT EXISTS (SELECT 1 FROM dw.v_model_forecast_return AS r WHERE r.return_no = a.return_no)
GROUP BY a.method, a.return_no
UNION ALL
SELECT 'common cells', CONCAT('a cell is common but does not have every method of its line: ', a.forecast_line, ' ', a.financial_year, ' R', a.return_no, ' ', a.department_group_code)
FROM dw.v_model_forecast_accuracy AS a
WHERE a.common_cells = 1
GROUP BY a.forecast_line, a.financial_year, a.return_no, a.department_group_code, a.budget_measure
HAVING COUNT(DISTINCT a.method) <> CASE a.forecast_line WHEN 'Pay' THEN 4 ELSE 3 END
UNION ALL
SELECT 'common cells', CONCAT('a cell has every method of its line but is not common: ', a.forecast_line, ' ', a.financial_year, ' R', a.return_no, ' ', a.department_group_code)
FROM dw.v_model_forecast_accuracy AS a
WHERE a.common_cells = 0
GROUP BY a.forecast_line, a.financial_year, a.return_no, a.department_group_code, a.budget_measure
HAVING COUNT(DISTINCT a.method) = CASE a.forecast_line WHEN 'Pay' THEN 4 ELSE 3 END
UNION ALL
SELECT 'mape', CONCAT('mape columns set below GBP 100m or missing above it: ', forecast_line, ' ', financial_year, ' R', return_no, ' ', department_group_code, ' ', method)
FROM dw.v_model_forecast_accuracy
WHERE (mape_outturn IS NOT NULL AND mape_outturn < 100000) OR (mape_outturn IS NULL AND full_year_outturn >= 100000)
UNION ALL
SELECT CONCAT(OBJECT_SCHEMA_NAME(d.referencing_id), '.', OBJECT_NAME(d.referencing_id)),
       CONCAT('reads ', d.referenced_schema_name, '.', d.referenced_entity_name, ', which is not on the list of real sources')
FROM sys.sql_expression_dependencies AS d
WHERE d.referencing_id IN (OBJECT_ID('dw.v_model_forecast_accuracy'), OBJECT_ID('dw.v_model_forecast_method'), OBJECT_ID('dw.v_model_forecast_return'))
  AND d.referenced_id IS NOT NULL
  AND CONCAT(d.referenced_schema_name, '.', d.referenced_entity_name) NOT IN
      ('dw.forecast_accuracy', 'dw.forecast_pay_accuracy', 'dw.forecast_group_department', 'dw.forecast_return',
       'audit.forecast_fte_cost_coverage');
