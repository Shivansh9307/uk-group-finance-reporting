-- scope: full
-- The model's view layer, part 10: the plan variance check the Variance page reads (needs the audit table, so full scope only).
--   dw.v_model_plan_variance  audit.plan_variance_reconciliation: every plan variance from FY2022-23, one row per financial
--                             year x Spending Review group x plan measure, with the independent outturn, the gaps and the
--                             verdict. Audit and control, not a fact: nothing reads it into an outturn or plan total.
-- Columns are copied from the audit table; no amount is recalculated.

DROP VIEW IF EXISTS dw.v_model_plan_variance;
GO
CREATE VIEW dw.v_model_plan_variance
AS
SELECT financial_year, sr_group_name, measure, plan_amount, outturn, variance, variance_share, reference_source, outturn_reference,
       gap_plan_only, gap_outturn_only, gap_first_look, gap_on_reference, residual, first_look_cause, verdict_class, verdict
FROM audit.plan_variance_reconciliation;
GO
