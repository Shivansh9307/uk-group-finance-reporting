-- test: all 204 sub-segments that the June 2023 release reports under the BEIS department map to DSIT, DESNZ, DBT or the BEIS Unallocated member, never to a department that no longer exists
WITH beis AS (
    SELECT DISTINCT m.organisation_key, s.sub_segment_code
    FROM stg.inyear_snapshot AS s
    JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
    JOIN dw.dim_department AS d ON d.department_key = m.department_key
    WHERE s.release = '2023-06' AND d.department_number = '084'
)
SELECT b.organisation_key, b.sub_segment_code, d.department_number, d.department_name AS problem
FROM beis AS b
JOIN dw.current_structure_line AS l ON l.organisation_key = b.organisation_key AND l.sub_segment_code = b.sub_segment_code
JOIN dw.dim_department AS d ON d.department_key = l.current_department_key
WHERE d.department_number NOT IN ('084', '013', '066', 'U084')
   OR (d.department_number = '084' AND d.is_current = 0)
UNION ALL
SELECT NULL, NULL, NULL, CONCAT('distinct sub-segments in the set: ', COUNT(DISTINCT sub_segment_code), ' instead of 204')
FROM beis
HAVING COUNT(DISTINCT sub_segment_code) <> 204;
