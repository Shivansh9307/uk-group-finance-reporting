-- test: every authored current-structure row is unique, names a durable key that exists, decides at least one line (no dead row), puts those lines in the department it names, and an estimated row is flagged on the lines it decides
SELECT a.authored_row, 'duplicate key' AS problem
FROM stg.current_structure_authored AS a
WHERE EXISTS (SELECT 1 FROM stg.current_structure_authored b
              WHERE b.authored_row <> a.authored_row AND b.durable_key = a.durable_key
                AND ISNULL(b.sub_segment_code, N'') = ISNULL(a.sub_segment_code, N''))
UNION ALL
SELECT a.authored_row, 'durable key not in dim_organisation'
FROM stg.current_structure_authored AS a
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_organisation o WHERE o.durable_key = a.durable_key)
UNION ALL
SELECT a.authored_row, 'decides no line'
FROM stg.current_structure_authored AS a
WHERE NOT EXISTS (SELECT 1 FROM dw.current_structure_line l WHERE l.authored_row = a.authored_row)
UNION ALL
SELECT a.authored_row, 'a decided line is in another department or has another estimate flag'
FROM stg.current_structure_authored AS a
JOIN dw.current_structure_line AS l ON l.authored_row = a.authored_row
JOIN dw.dim_department AS d ON d.department_key = l.current_department_key
WHERE d.department_number <> a.current_department_number OR l.is_estimated <> a.is_estimated
UNION ALL
SELECT l.organisation_key, 'estimated line without an estimated authored row'
FROM dw.current_structure_line AS l
WHERE l.is_estimated = 1
  AND NOT EXISTS (SELECT 1 FROM stg.current_structure_authored a WHERE a.authored_row = l.authored_row AND a.is_estimated = 1);
