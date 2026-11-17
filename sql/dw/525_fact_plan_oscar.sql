-- scope: full
-- Grain A of dw.fact_plan: OSCAR Plans at financial year x organisation x control budget detail x economic
-- budget, summed from stg.plan_oscar (which holds them at organisation x economic category). Needs the annual
-- extracts, so this file runs in a full-scope build only. Keys continue after the rows of dw/520.
-- measure: DEL programme and administration are RDEL (resource) or CDEL (capital), where RDEL includes
-- depreciation; departmental AME is RAME or CAME; NON_DEPT_AME and NON_BUDGET as OSCAR names them. DEL rows with
-- economic budget n/a are UNCLASSIFIED (a few keys a year, under GBP 1bn in total).

WITH oscar AS (
    SELECT
        'A' AS grain_code, ps.plan_source_key, o.financial_year, g.sr_group_key, o.organisation_code,
        o.control_budget_detail, o.economic_budget AS economic_budget,
        CASE WHEN o.control_budget_detail IN ('DEL PROG', 'DEL ADMIN') AND o.economic_budget = 'RESOURCE' THEN 'RDEL'
             WHEN o.control_budget_detail IN ('DEL PROG', 'DEL ADMIN') AND o.economic_budget = 'CAPITAL' THEN 'CDEL'
             WHEN o.control_budget_detail = 'DEPT AME' AND o.economic_budget = 'RESOURCE' THEN 'RAME'
             WHEN o.control_budget_detail = 'DEPT AME' AND o.economic_budget = 'CAPITAL' THEN 'CAME'
             WHEN o.control_budget_detail = 'NON-DEPT AME' THEN 'NON_DEPT_AME'
             WHEN o.control_budget_detail = 'NON-BUDGET' THEN 'NON_BUDGET'
             ELSE 'UNCLASSIFIED' END AS measure,
        SUM(o.amount) AS amount, SUM(o.source_rows) AS source_line_count, CAST(0 AS bit) AS is_part_of_other_measure
    FROM stg.plan_oscar AS o
    JOIN stg.plan_name_map AS m ON m.name_family = 'oscar_extract' AND m.plan_name = o.sr_group_name
    JOIN dw.dim_sr_group AS g ON g.sr_group_name = m.target_name
    JOIN dw.dim_plan_source AS ps ON ps.plan_source_code = 'OSCAR_PLANS_2022_11'
    GROUP BY ps.plan_source_key, o.financial_year, g.sr_group_key, o.organisation_code, o.control_budget_detail,
             o.economic_budget
)

INSERT INTO dw.fact_plan
    (plan_fact_key, plan_source_key, financial_year, sr_group_key, organisation_code, control_budget_detail,
     economic_budget, measure, amount, grain_code, source_line_count, is_part_of_other_measure)
SELECT
    (SELECT COALESCE(MAX(plan_fact_key), 0) FROM dw.fact_plan)
      + ROW_NUMBER() OVER (ORDER BY a.plan_source_key, a.financial_year, a.sr_group_key, a.organisation_code,
                                    a.control_budget_detail, a.economic_budget, a.measure),
    a.plan_source_key, a.financial_year, a.sr_group_key, a.organisation_code, a.control_budget_detail,
    a.economic_budget, a.measure, a.amount, a.grain_code, a.source_line_count, a.is_part_of_other_measure
FROM oscar AS a;
GO
