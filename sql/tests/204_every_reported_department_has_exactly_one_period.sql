-- test: every department number reported in a release has exactly one authored naming period covering that release
SELECT r.release_seq, r.department_number, COUNT(d.department_key) AS periods
FROM (SELECT DISTINCT release_seq, department_number FROM stg.organisation_release) AS r
LEFT JOIN dw.dim_department AS d
  ON d.department_number = r.department_number AND d.member_type <> 'Unknown'
 AND r.release_seq BETWEEN d.valid_from_release_seq AND d.valid_to_release_seq
GROUP BY r.release_seq, r.department_number
HAVING COUNT(d.department_key) <> 1;
