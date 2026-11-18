-- The model's view layer, part 4: what the plan facts relate to.
--   dw.v_model_sr_group     dw.dim_sr_group
--   dw.v_model_plan_source  dw.dim_plan_source
--   dw.v_model_plan_grain   dw.dim_plan_grain

DROP VIEW IF EXISTS dw.v_model_sr_group;
GO
CREATE VIEW dw.v_model_sr_group
AS
SELECT sr_group_key, sr_group_code, sr_group_name, member_type, is_department_group, has_outturn, description
FROM dw.dim_sr_group;
GO

DROP VIEW IF EXISTS dw.v_model_plan_source;
GO
CREATE VIEW dw.v_model_plan_source
AS
SELECT plan_source_key, plan_source_code, family, edition, edition_label, plan_year, first_published,
       grain_description, plan_basis, includes_block_grant_adjustment, scotland_bga_flag, scotland_bga_rule,
       resource_basis, resource_basis_evidence, is_final_plan_for_year
FROM dw.dim_plan_source;
GO

DROP VIEW IF EXISTS dw.v_model_plan_grain;
GO
CREATE VIEW dw.v_model_plan_grain
AS
SELECT grain_code, grain_name, description
FROM dw.dim_plan_grain;
GO
