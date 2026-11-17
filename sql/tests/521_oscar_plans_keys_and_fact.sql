-- test: every OSCAR plan key has one department group and one Spending Review group, every plan row has an amount that parses, all rows are PLANS rows with a recognised control budget, and the grain A rows of dw.fact_plan carry the whole OSCAR total
-- marker: localdata
-- requires: raw.plan_oscar, raw.plan_oscar_expected, raw.plan_source_file, stg.plan_oscar
SELECT 'key with more than one department group or Spending Review group' AS problem, financial_year AS k1, organisation_code AS k2, NULL AS k3
FROM (
    SELECT o.year_short_name AS financial_year, o.organisation_code
    FROM raw.plan_oscar AS o
    GROUP BY o.year_short_name, o.organisation_code
    HAVING COUNT(DISTINCT o.department_group_code) > 1 OR COUNT(DISTINCT o.sr_group_code) > 1
) AS x
UNION ALL
SELECT 'amount does not parse', CAST(file_id AS varchar(10)), CAST(source_row AS varchar(10)), amount_text
FROM raw.plan_oscar WHERE TRY_CAST(LTRIM(RTRIM(amount_text)) AS decimal(19,4)) IS NULL
UNION ALL
SELECT 'row is not a PLANS row', CAST(file_id AS varchar(10)), CAST(source_row AS varchar(10)), version_code
FROM raw.plan_oscar WHERE version_code <> 'PLANS' OR usage_code NOT IN ('PLANS', 'BOTH', 'OUTTURN')
UNION ALL
-- 37 rows of the PLANS version carry usage OUTTURN (DHSC pension and housing revenue account lines and a few
-- DCMS bodies). They are in the control totals, so they stay in; the count is pinned so that a change is seen.
SELECT 'rows of the PLANS version with usage OUTTURN changed', NULL, NULL, CAST(COUNT(*) AS varchar(20))
FROM raw.plan_oscar WHERE usage_code = 'OUTTURN'
HAVING COUNT(*) <> 37
UNION ALL
SELECT 'plan row not in Period 0', CAST(file_id AS varchar(10)), CAST(source_row AS varchar(10)), month_short_name
FROM raw.plan_oscar WHERE month_short_name NOT LIKE 'Period 0 - %'
UNION ALL
SELECT 'unrecognised control budget', control_budget_l1_name, NULL, NULL
FROM raw.plan_oscar
WHERE control_budget_l1_name NOT IN ('DEPARTMENTAL EXPENDITURE LIMITS PROGRAMME', 'DEPARTMENTAL EXPENDITURE LIMITS ADMINISTRATION',
      'DEPARTMENTAL ANNUALLY MANAGED EXPENDITURE', 'NON-DEPARTMENTAL ANNUALLY MANAGED EXPENDITURE', 'NON-BUDGET (NB)')
GROUP BY control_budget_l1_name
UNION ALL
SELECT 'fact grain A total differs from the raw plan rows', financial_year, NULL, CAST(f.amount AS varchar(40))
FROM (SELECT financial_year, SUM(amount) AS amount FROM dw.fact_plan WHERE grain_code = 'A' GROUP BY financial_year) AS f
WHERE f.amount <> (SELECT SUM(CAST(LTRIM(RTRIM(o.amount_text)) AS decimal(19,4))) FROM raw.plan_oscar AS o WHERE o.year_short_name = f.financial_year)
UNION ALL
SELECT 'fact grain A total differs from stg.plan_oscar', f.financial_year, NULL, CAST(f.amount AS varchar(40))
FROM (SELECT financial_year, SUM(amount) AS amount FROM dw.fact_plan WHERE grain_code = 'A' GROUP BY financial_year) AS f
WHERE f.amount <> (SELECT SUM(amount) FROM stg.plan_oscar AS s WHERE s.financial_year = f.financial_year)
UNION ALL
SELECT 'raw plan row count differs from stg source rows', NULL, NULL, CAST(COUNT(*) AS varchar(20))
FROM raw.plan_oscar
HAVING COUNT(*) <> (SELECT COALESCE(SUM(source_rows), 0) FROM stg.plan_oscar);
