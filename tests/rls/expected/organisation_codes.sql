-- Independent of the model: the distinct organisation codes of the organisation dimension (a dimension is not filtered
-- by department).
SELECT COUNT(DISTINCT organisation_code) AS organisation_codes FROM dw.dim_organisation;
