-- The model's view layer, part 2: the three reference dimensions of an outturn line.
--   dw.v_model_account         dw.dim_account
--   dw.v_model_control_budget  dw.dim_control_budget
--   dw.v_model_segment         dw.dim_segment

DROP VIEW IF EXISTS dw.v_model_account;
GO
CREATE VIEW dw.v_model_account
AS
SELECT account_key, economic_category_code, economic_category_name, economic_category_label,
       pesa_economic_group_code, pesa_economic_group, economic_budget, flow, flow_basis, source_codes,
       first_release, last_release
FROM dw.dim_account;
GO

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
