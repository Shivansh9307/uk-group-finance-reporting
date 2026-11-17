-- test: the department_key in the release map is the department number of the code, in the naming period covering the release
SELECT m.release, m.organisation_code, m.department_key
FROM dw.organisation_release_map AS m
JOIN dw.dim_department AS d ON d.department_key = m.department_key
WHERE d.department_number <> RIGHT(m.organisation_code, 3)
   OR m.release_seq NOT BETWEEN d.valid_from_release_seq AND d.valid_to_release_seq;
