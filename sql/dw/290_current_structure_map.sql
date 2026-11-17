-- stg.current_structure_map: which department each (organisation version, sub-segment) belongs to in the
-- CURRENT structure. A view, with a column contract that later work keeps and only replaces the rule
-- behind (it lives in the dw folder because it reads dw tables; the object is in stg):
--   organisation_key         dw.dim_organisation
--   sub_segment_code         as published
--   current_department_key   dw.dim_department
--   method                   how the department was chosen
--   is_estimated             1 where the department is an estimate rather than a published fact
-- Default rule: the department of the latest version of the durable key. When that department is not a
-- current department (BEIS core, whose spending moved to three departments) the department is kept as it
-- is and the method says so, so the case is visible and can be taken over by a sub-segment-based mapping.
-- Covers every (organisation_key, sub_segment_code) pair in stg.inyear_snapshot exactly once.

DROP VIEW IF EXISTS stg.current_structure_map;
GO

CREATE VIEW stg.current_structure_map
AS
SELECT p.organisation_key,
       p.sub_segment_code,
       l.department_key AS current_department_key,
       CAST(CASE WHEN d.is_current = 1 THEN 'durable key latest version' ELSE 'department not current' END
            AS varchar(40)) AS method,
       CAST(0 AS bit) AS is_estimated
FROM (
    SELECT DISTINCT m.organisation_key, s.sub_segment_code
    FROM stg.inyear_snapshot AS s
    JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
) AS p
JOIN dw.dim_organisation AS o ON o.organisation_key = p.organisation_key
JOIN dw.dim_organisation AS l ON l.durable_key = o.durable_key AND l.is_latest_version = 1
JOIN dw.dim_department AS d ON d.department_key = l.department_key;
GO
