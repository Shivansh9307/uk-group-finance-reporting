-- Independent of the model: for each relationship, the rows of the many side that have no row on the one side,
-- by anti-join on dw base tables.
SELECT N'Fact Outturn to Release' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_outturn) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_outturn AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_release AS d WHERE d.release_key = f.release_key)) AS rows_without_member
UNION ALL
SELECT N'Fact Outturn to Organisation (as reported)' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_outturn) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_outturn AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_organisation AS d WHERE d.organisation_key = f.organisation_key)) AS rows_without_member
UNION ALL
SELECT N'Fact Outturn to Department (current structure)' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_outturn) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_outturn AS f WHERE NOT EXISTS (SELECT 1 FROM dw.current_structure_department AS d WHERE d.department_key = f.current_department_key AND d.is_live = 1)) AS rows_without_member
UNION ALL
SELECT N'Fact Outturn to Sub-Segment' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_outturn) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_outturn AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_segment AS d WHERE d.segment_key = f.segment_key)) AS rows_without_member
UNION ALL
SELECT N'Fact Outturn to Account' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_outturn) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_outturn AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_account AS d WHERE d.account_key = f.account_key)) AS rows_without_member
UNION ALL
SELECT N'Fact Outturn to Control Budget' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_outturn) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_outturn AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_control_budget AS d WHERE d.control_budget_key = f.control_budget_key)) AS rows_without_member
UNION ALL
SELECT N'Fact Outturn to Fiscal Period' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_outturn) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_outturn AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_period AS d WHERE d.period_key = f.period_key)) AS rows_without_member
UNION ALL
SELECT N'Fact Outturn to Scenario' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_outturn) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_outturn AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_scenario AS d WHERE d.scenario_key = f.scenario_key)) AS rows_without_member
UNION ALL
SELECT N'Fact Outturn to Spending Review Group' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_outturn) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_outturn AS f JOIN dw.dim_segment AS s ON s.segment_key = f.segment_key LEFT JOIN dw.outturn_sr_group_bridge AS b ON b.organisation_key = f.organisation_key AND b.sub_segment_code = s.sub_segment_code WHERE NOT EXISTS (SELECT 1 FROM dw.dim_sr_group AS d WHERE d.sr_group_key = b.sr_group_key)) AS rows_without_member
UNION ALL
SELECT N'Fact Outturn to Data Quality Issue' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_outturn) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_outturn AS f WHERE f.dq_issue_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dw.dq_issue AS d WHERE d.dq_issue_id = f.dq_issue_id)) AS rows_without_member
UNION ALL
SELECT N'Fact Plan to Plan Source' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_plan) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_plan AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_plan_source AS d WHERE d.plan_source_key = f.plan_source_key)) AS rows_without_member
UNION ALL
SELECT N'Fact Plan to Fiscal Year' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_plan) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_plan AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_period AS d WHERE d.financial_year = f.financial_year)) AS rows_without_member
UNION ALL
SELECT N'Fact Plan to Spending Review Group' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_plan) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_plan AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_sr_group AS d WHERE d.sr_group_key = f.sr_group_key)) AS rows_without_member
UNION ALL
SELECT N'Fact Plan to Scenario' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_plan) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_plan AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_scenario AS d WHERE d.scenario_name = N'Plan')) AS rows_without_member
UNION ALL
SELECT N'Fact Plan to Plan Grain' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_plan) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_plan AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_plan_grain AS d WHERE d.grain_code = f.grain_code)) AS rows_without_member
UNION ALL
SELECT N'Fact Plan Phased to Fiscal Period' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_plan_phased) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_plan_phased AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_period AS d WHERE d.period_key = f.period_key)) AS rows_without_member
UNION ALL
SELECT N'Fact Plan Phased to Plan Source' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_plan_phased) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_plan_phased AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_plan_source AS d WHERE d.plan_source_key = f.plan_source_key)) AS rows_without_member
UNION ALL
SELECT N'Fact Plan Phased to Spending Review Group' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_plan_phased) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_plan_phased AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_sr_group AS d WHERE d.sr_group_key = f.sr_group_key)) AS rows_without_member
UNION ALL
SELECT N'Fact Plan Phased to Scenario' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_plan_phased) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_plan_phased AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_scenario AS d WHERE d.scenario_key = f.scenario_key)) AS rows_without_member
UNION ALL
SELECT N'Fact Plan Phased to Plan Grain' AS relationship, (SELECT COUNT_BIG(*) FROM dw.fact_plan_phased) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.fact_plan_phased AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_plan_grain AS d WHERE d.grain_code = f.grain_code)) AS rows_without_member
UNION ALL
SELECT N'Fiscal Period to Fiscal Year' AS relationship, (SELECT COUNT_BIG(*) FROM dw.dim_period) AS many_side_rows, (SELECT COUNT_BIG(*) FROM dw.dim_period AS f WHERE f.financial_year IS NULL) AS rows_without_member
ORDER BY relationship;
