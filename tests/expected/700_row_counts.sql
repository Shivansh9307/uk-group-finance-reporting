-- Independent of the model views: counts of the dw base tables, with the same documented subsets.
SELECT N'Fact Outturn' AS table_name, COUNT_BIG(*) AS row_count FROM dw.fact_outturn
UNION ALL
SELECT N'Fact Plan' AS table_name, COUNT_BIG(*) AS row_count FROM dw.fact_plan
UNION ALL
SELECT N'Fact Plan Phased (derived)' AS table_name, COUNT_BIG(*) AS row_count FROM dw.fact_plan_phased
UNION ALL
SELECT N'Fiscal Year' AS table_name, COUNT_BIG(DISTINCT financial_year) AS row_count FROM dw.dim_period
UNION ALL
SELECT N'Fiscal Period' AS table_name, COUNT_BIG(*) AS row_count FROM dw.dim_period
UNION ALL
SELECT N'Release' AS table_name, COUNT_BIG(*) AS row_count FROM dw.dim_release
UNION ALL
SELECT N'Scenario' AS table_name, COUNT_BIG(*) AS row_count FROM dw.dim_scenario
UNION ALL
SELECT N'Account' AS table_name, COUNT_BIG(*) AS row_count FROM dw.dim_account
UNION ALL
SELECT N'Control Budget' AS table_name, COUNT_BIG(*) AS row_count FROM dw.dim_control_budget
UNION ALL
SELECT N'Sub-Segment' AS table_name, COUNT_BIG(*) AS row_count FROM dw.dim_segment
UNION ALL
SELECT N'Organisation (as reported)' AS table_name, COUNT_BIG(*) AS row_count FROM dw.dim_organisation
UNION ALL
SELECT N'Department (current structure)' AS table_name, COUNT_BIG(*) AS row_count FROM dw.current_structure_department WHERE is_live = 1
UNION ALL
SELECT N'Spending Review Group' AS table_name, COUNT_BIG(*) AS row_count FROM dw.dim_sr_group
UNION ALL
SELECT N'Plan Source' AS table_name, COUNT_BIG(*) AS row_count FROM dw.dim_plan_source
UNION ALL
SELECT N'Plan Grain' AS table_name, COUNT_BIG(*) AS row_count FROM dw.dim_plan_grain
UNION ALL
SELECT N'Data Quality Issue' AS table_name, COUNT_BIG(*) + 1 AS row_count FROM dw.dq_issue
ORDER BY table_name;
