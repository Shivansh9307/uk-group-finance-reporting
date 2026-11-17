-- test: OSCAR Plans have 8,902 rows at the load grain for FY2019-20 to FY2021-22, the rows read per extract equal the extract's own plan row count, and the totals tie to plan_oscar_totals.csv per year, department group, control budget detail and economic budget (amounts and source row counts)
-- marker: localdata
-- requires: raw.plan_oscar, raw.plan_oscar_expected, raw.plan_source_file, stg.plan_oscar
SELECT 'row count' AS control, '2019-20 to 2021-22' AS key1, CAST(COUNT(*) AS varchar(40)) AS actual, '8902' AS expected
FROM stg.plan_oscar WHERE financial_year IN ('2019-20', '2020-21', '2021-22')
HAVING COUNT(*) <> 8902
UNION ALL
SELECT 'plan rows per extract', f.filename, CAST(f.rows_loaded AS varchar(40)), CAST(e.plans_rows AS varchar(40))
FROM raw.plan_source_file AS f
JOIN raw.plan_oscar AS o ON o.file_id = f.file_id
JOIN raw.plan_oscar_expected AS e ON e.control = 'file_plans_rows' AND e.fiscal_year = o.year_short_name
WHERE f.family = 'oscar_extract'
GROUP BY f.filename, f.rows_loaded, e.plans_rows
HAVING f.rows_loaded <> e.plans_rows OR f.rows_loaded <> COUNT(*)
UNION ALL
SELECT 'extract files', 'count', CAST(COUNT(*) AS varchar(40)), '5'
FROM raw.plan_source_file WHERE family = 'oscar_extract'
HAVING COUNT(*) <> 5
UNION ALL
SELECT 'group total', e.fiscal_year + ' ' + e.department_group_code + ' ' + e.control_budget_detail + ' ' + e.economic_budget,
       COALESCE(CAST(s.amount AS varchar(40)), 'missing') + ' rows ' + COALESCE(CAST(s.rows AS varchar(10)), '0'),
       e.plans_gbp_thousand + ' rows ' + CAST(e.plans_rows AS varchar(10))
FROM raw.plan_oscar_expected AS e
LEFT JOIN (
    SELECT financial_year, department_group_code, control_budget_detail, economic_budget, SUM(amount) AS amount, SUM(source_rows) AS rows
    FROM stg.plan_oscar GROUP BY financial_year, department_group_code, control_budget_detail, economic_budget
) AS s
  ON s.financial_year = e.fiscal_year AND s.department_group_code = e.department_group_code
 AND s.control_budget_detail = e.control_budget_detail AND s.economic_budget = e.economic_budget
WHERE e.control = 'group_totals'
  AND (e.plans_rows > 0 OR e.plans_gbp_thousand <> '0')   -- the control csv also lists combinations that have outturn but no plan rows
  AND (s.amount IS NULL OR s.amount <> CAST(e.plans_gbp_thousand AS decimal(19,4)) OR s.rows <> e.plans_rows)
UNION ALL
SELECT 'group total', s.financial_year + ' ' + s.department_group_code + ' ' + s.control_budget_detail + ' ' + s.economic_budget,
       CAST(s.amount AS varchar(40)), 'not in the control csv'
FROM (SELECT financial_year, department_group_code, control_budget_detail, economic_budget, SUM(amount) AS amount
      FROM stg.plan_oscar GROUP BY financial_year, department_group_code, control_budget_detail, economic_budget) AS s
WHERE NOT EXISTS (SELECT 1 FROM raw.plan_oscar_expected AS e
                  WHERE e.control = 'group_totals' AND e.fiscal_year = s.financial_year AND e.department_group_code = s.department_group_code
                    AND e.control_budget_detail = s.control_budget_detail AND e.economic_budget = s.economic_budget);
