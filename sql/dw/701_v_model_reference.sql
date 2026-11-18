-- The model's view layer, part 2: the two reference dimensions of an outturn line that carry no other logic.
--   (dw.v_model_account is in 741, because it carries the statement line of each account)
--   dw.v_model_control_budget  dw.dim_control_budget
--   dw.v_model_segment         dw.dim_segment

DROP VIEW IF EXISTS dw.v_model_control_budget;
GO
CREATE VIEW dw.v_model_control_budget
AS
SELECT control_budget_key, control_budget_detail_code, control_budget_detail, control_budget, published_labels,
       first_release, last_release
FROM dw.dim_control_budget;
GO

DROP VIEW IF EXISTS dw.v_model_segment;
GO
CREATE VIEW dw.v_model_segment
AS
SELECT segment_key, sub_segment_code, segment_name, segment_label, first_release, last_release, n_releases
FROM dw.dim_segment;
GO
