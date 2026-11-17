-- test: stg.current_structure_map has exactly one row for every (organisation_key, sub_segment_code) pair in the snapshot, and no other
WITH pairs AS (
    SELECT DISTINCT m.organisation_key, s.sub_segment_code
    FROM stg.inyear_snapshot AS s
    JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
), v AS (
    SELECT organisation_key, sub_segment_code, COUNT(*) AS n FROM stg.current_structure_map GROUP BY organisation_key, sub_segment_code
)
SELECT p.organisation_key, p.sub_segment_code, ISNULL(v.n, 0) AS rows_in_view
FROM pairs AS p LEFT JOIN v ON v.organisation_key = p.organisation_key AND v.sub_segment_code = p.sub_segment_code
WHERE ISNULL(v.n, 0) <> 1
UNION ALL
SELECT v.organisation_key, v.sub_segment_code, v.n
FROM v WHERE NOT EXISTS (SELECT 1 FROM pairs p WHERE p.organisation_key = v.organisation_key AND p.sub_segment_code = v.sub_segment_code);
