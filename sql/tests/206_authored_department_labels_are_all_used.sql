-- test: every label listed in published_labels is published at least once inside its period (no stale evidence)
SELECT p.department_number, p.valid_from_seq, LTRIM(RTRIM(s.value)) AS label
FROM stg.department_period AS p
CROSS APPLY STRING_SPLIT(p.published_labels, '|') AS s
WHERE p.member_type = 'Department'
  AND NOT EXISTS (
    SELECT 1 FROM stg.organisation_release r
    WHERE r.department_number = p.department_number AND r.release_seq BETWEEN p.valid_from_seq AND p.valid_to_seq
      AND UPPER(LTRIM(RTRIM(r.department_label))) = UPPER(LTRIM(RTRIM(s.value))));
