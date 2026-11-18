-- The model's view layer, part 3: the two role-playing organisation dimensions.
--   dw.v_model_organisation   dw.dim_organisation, one row per version (Type 2), with the department the
--                             releases of that version reported it under (a join, to expose its name and number)
--   dw.v_model_department     the departments of the current structure: the rows of dw.dim_department that
--                             dw.current_structure_department marks is_live (the fact's current_department_key
--                             only ever points at those; a closed naming period never receives a line)

DROP VIEW IF EXISTS dw.v_model_organisation;
GO
CREATE VIEW dw.v_model_organisation
AS
SELECT o.organisation_key, o.durable_key, o.version_no, o.organisation_code, o.organisation_name,
       d.department_number AS department_number_as_reported, d.department_name AS department_name_as_reported,
       o.valid_from_release, o.valid_to_release, o.n_releases_reported, o.version_reason, o.durable_key_rule,
       o.successor_durable_key, o.is_current, o.is_latest_version
FROM dw.dim_organisation AS o
JOIN dw.dim_department AS d ON d.department_key = o.department_key;
GO

DROP VIEW IF EXISTS dw.v_model_department;
GO
CREATE VIEW dw.v_model_department
AS
SELECT d.department_key, d.department_number, d.department_name, d.member_type, d.valid_from_release,
       d.valid_to_release
FROM dw.dim_department AS d
JOIN dw.current_structure_department AS c ON c.department_key = d.department_key
WHERE c.is_live = 1;
GO
