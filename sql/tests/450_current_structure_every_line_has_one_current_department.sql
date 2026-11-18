-- test: every (organisation_key, sub_segment_code) in the snapshot maps to exactly one department that exists now or to an Unallocated member that exists, never to Unknown, a closed department or a missing key
WITH pairs AS (
    SELECT DISTINCT m.organisation_key, s.sub_segment_code
    FROM stg.inyear_snapshot AS s
    JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
), latest AS (
    SELECT MAX(release_seq) AS latest_seq, MAX(CASE WHEN highest_period = 12 THEN release_seq END) AS latest_ye_seq FROM stg.release
)
SELECT p.organisation_key, p.sub_segment_code, 'not exactly one row' AS problem, COUNT(c.organisation_key) AS n
FROM pairs AS p
LEFT JOIN dw.current_structure_line AS c ON c.organisation_key = p.organisation_key AND c.sub_segment_code = p.sub_segment_code
GROUP BY p.organisation_key, p.sub_segment_code
HAVING COUNT(c.organisation_key) <> 1
UNION ALL
SELECT c.organisation_key, c.sub_segment_code, 'department does not exist, is Unknown or is closed', 1
FROM dw.current_structure_line AS c
CROSS JOIN latest AS t
LEFT JOIN dw.dim_department AS d ON d.department_key = c.current_department_key
WHERE d.department_key IS NULL
   OR d.member_type = 'Unknown'
   OR (d.member_type = 'Department' AND d.is_current = 0
       AND NOT (d.valid_to_release_seq = t.latest_seq
                AND EXISTS (SELECT 1 FROM stg.organisation_release r
                            WHERE r.release_seq = t.latest_ye_seq AND r.department_number = d.department_number)))
UNION ALL
SELECT c.organisation_key, c.sub_segment_code, 'method outside the list', 1
FROM dw.current_structure_line AS c
WHERE c.method NOT IN ('authored line', 'authored organisation', 'sub-segment code', 'sub-segment name',
                       'organisation current department', 'organisation successor', 'unallocated former department')
UNION ALL
SELECT c.organisation_key, c.sub_segment_code, 'view differs from the table', 1
FROM dw.current_structure_line AS c
LEFT JOIN stg.current_structure_map AS v
  ON v.organisation_key = c.organisation_key AND v.sub_segment_code = c.sub_segment_code
 AND v.current_department_key = c.current_department_key AND v.method = c.method AND v.is_estimated = c.is_estimated
WHERE v.organisation_key IS NULL;
