-- test: no department number carries two department labels in one release
SELECT release_seq, department_number, COUNT(DISTINCT department_label) AS labels
FROM stg.organisation_release
GROUP BY release_seq, department_number
HAVING COUNT(DISTINCT department_label) > 1;
