-- The model's view layer, part 6: the three fact tables.
--   dw.v_model_fact_outturn       dw.fact_outturn (real revision deltas). Two joins expose keys the model
--                                 needs: sr_group_key from dw.outturn_sr_group_bridge (organisation version
--                                 and sub-segment, one row each, so no row is added or lost) and dq_issue_key,
--                                 which is dq_issue_id with NULL written as 0. department_key (the department as
--                                 the release reports it) is not exposed: the organisation version carries it.
--   dw.v_model_fact_plan          dw.fact_plan (real, as published) with scenario_key of the Plan scenario
--   dw.v_model_fact_plan_phased   dw.fact_plan_phased. DERIVED: the monthly plan is my allocation of a published
--                                 annual plan, not a published number; is_derived and method travel with it.
--                                 It is the one view allowed to read dw.fact_plan_phased (tests 558 and 706).

DROP VIEW IF EXISTS dw.v_model_fact_outturn;
GO
CREATE VIEW dw.v_model_fact_outturn
AS
SELECT f.release_key, f.organisation_key, f.current_department_key, f.segment_key, f.account_key,
       f.control_budget_key, f.period_key, f.scenario_key, b.sr_group_key,
       ISNULL(f.dq_issue_id, 0) AS dq_issue_key, f.amount_delta, f.revision_no
FROM dw.fact_outturn AS f
JOIN dw.dim_segment AS s ON s.segment_key = f.segment_key
JOIN dw.outturn_sr_group_bridge AS b
  ON b.organisation_key = f.organisation_key AND b.sub_segment_code = s.sub_segment_code;
GO

DROP VIEW IF EXISTS dw.v_model_fact_plan;
GO
CREATE VIEW dw.v_model_fact_plan
AS
SELECT p.plan_fact_key, p.plan_source_key, p.financial_year, p.sr_group_key, sc.scenario_key,
       p.organisation_code, p.control_budget_detail, p.economic_budget, p.measure, p.grain_code, p.amount,
       p.source_line_count, p.is_part_of_other_measure
FROM dw.fact_plan AS p
JOIN dw.dim_scenario AS sc ON sc.scenario_name = N'Plan';
GO

DROP VIEW IF EXISTS dw.v_model_fact_plan_phased;
GO
CREATE VIEW dw.v_model_fact_plan_phased
AS
SELECT plan_fact_key, period_key, plan_source_key, sr_group_key, scenario_key, organisation_code,
       control_budget_detail, economic_budget, measure, grain_code, is_part_of_other_measure, share, amount,
       method, is_derived
FROM dw.fact_plan_phased;
GO
