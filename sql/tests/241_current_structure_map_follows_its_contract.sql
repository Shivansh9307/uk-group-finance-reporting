-- test: the current structure map keeps its contract: an allowed method, an estimate only on an authored line, and a line that follows its organisation stays in the department number of the durable key's latest version
SELECT c.organisation_key, c.sub_segment_code, c.method, c.is_estimated
FROM stg.current_structure_map AS c
JOIN dw.dim_organisation AS o ON o.organisation_key = c.organisation_key
JOIN dw.dim_organisation AS l ON l.durable_key = o.durable_key AND l.is_latest_version = 1
JOIN dw.dim_department AS ld ON ld.department_key = l.department_key
JOIN dw.dim_department AS d ON d.department_key = c.current_department_key
WHERE c.method NOT IN ('authored line', 'authored organisation', 'sub-segment code', 'sub-segment name',
                       'organisation current department', 'organisation successor', 'unallocated former department')
   OR (c.is_estimated = 1 AND c.method NOT LIKE 'authored%')
   OR (c.method = 'organisation current department' AND d.department_number <> ld.department_number);
