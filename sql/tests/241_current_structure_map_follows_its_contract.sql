-- test: the current structure map gives each pair the department of its durable key's latest version, with an allowed method and no estimate
SELECT c.organisation_key, c.sub_segment_code, c.method, c.is_estimated
FROM stg.current_structure_map AS c
JOIN dw.dim_organisation AS o ON o.organisation_key = c.organisation_key
JOIN dw.dim_organisation AS l ON l.durable_key = o.durable_key AND l.is_latest_version = 1
JOIN dw.dim_department AS d ON d.department_key = c.current_department_key
WHERE c.current_department_key <> l.department_key
   OR c.is_estimated <> 0
   OR c.method NOT IN ('durable key latest version', 'department not current')
   OR (c.method = 'durable key latest version' AND d.is_current = 0)
   OR (c.method = 'department not current' AND d.is_current = 1);
