-- The view the semantic model reads for the what-if settings.
--   dw.v_model_whatif_setting   one row per what-if setting: its name, the pay award and the headcount change in per cent, where each
--                               comes from, and whether it is the default
-- SYNTHETIC: read from synthetic.whatif_parameter and by nothing else; the table holds percentages and no amount. No fact, no view
-- of a fact and no real measure reads this view (sql/tests/940 and pipeline/tests/test_register.py).

DROP VIEW IF EXISTS dw.v_model_whatif_setting;
GO

CREATE VIEW dw.v_model_whatif_setting
AS
SELECT w.setting_key, w.setting_name, w.pay_award_pct, w.headcount_change_pct, w.pay_award_basis, w.headcount_basis,
       w.is_default
FROM synthetic.whatif_parameter AS w;
GO
