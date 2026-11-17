-- test: every row of stg.inyear_snapshot joins to the release map, and none lands on the Unknown member
SELECT TOP (20) s.release, s.organisation_code, s.sub_segment_code, m.organisation_key
FROM stg.inyear_snapshot AS s
LEFT JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
WHERE m.organisation_key IS NULL OR m.organisation_key <= 0 OR m.department_key <= 0;
