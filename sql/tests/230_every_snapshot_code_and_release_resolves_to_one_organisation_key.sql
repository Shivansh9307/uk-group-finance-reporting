-- test: every (organisation code, release) in stg.inyear_snapshot has exactly one row in the release map, and the map has no other rows
SELECT s.release, s.organisation_code, COUNT(m.organisation_key) AS mapped
FROM (SELECT DISTINCT release, organisation_code FROM stg.inyear_snapshot) AS s
LEFT JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
GROUP BY s.release, s.organisation_code
HAVING COUNT(m.organisation_key) <> 1
UNION ALL
SELECT m.release, m.organisation_code, 0
FROM dw.organisation_release_map AS m
WHERE NOT EXISTS (SELECT 1 FROM stg.inyear_snapshot s WHERE s.release = m.release AND s.organisation_code = m.organisation_code);
