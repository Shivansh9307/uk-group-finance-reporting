-- test: every department_key used by the organisation dimension or the release map exists in dim_department, and only Unknown has key -1
SELECT 'dim_organisation' AS used_by, o.organisation_key AS id, o.department_key
FROM dw.dim_organisation AS o
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_department d WHERE d.department_key = o.department_key)
UNION ALL
SELECT 'release_map', m.release_seq, m.department_key
FROM dw.organisation_release_map AS m
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_department d WHERE d.department_key = m.department_key)
UNION ALL
SELECT 'dim_department', d.department_key, d.department_key
FROM dw.dim_department AS d
WHERE (d.department_key = -1 AND d.member_type <> 'Unknown') OR (d.department_key <> -1 AND d.member_type = 'Unknown');
