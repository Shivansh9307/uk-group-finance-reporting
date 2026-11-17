-- test: every department label a release publishes is listed in published_labels of the authored period that covers it
SELECT r.release_seq, r.department_number, r.department_label
FROM (SELECT DISTINCT release_seq, department_number, department_label FROM stg.organisation_release) AS r
JOIN stg.department_period AS p
  ON p.department_number = r.department_number AND r.release_seq BETWEEN p.valid_from_seq AND p.valid_to_seq
WHERE NOT EXISTS (
    SELECT 1 FROM STRING_SPLIT(p.published_labels, '|') AS s
    WHERE UPPER(LTRIM(RTRIM(s.value))) = UPPER(LTRIM(RTRIM(r.department_label)))
);
