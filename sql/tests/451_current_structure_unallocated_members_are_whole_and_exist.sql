-- test: an Unallocated member is used only for the former department it is named after, exists with member_type Unallocated, and no Unallocated line is estimated or authored
SELECT c.organisation_key, c.sub_segment_code, d.department_number, fd.department_number AS former_number, c.method
FROM dw.current_structure_line AS c
JOIN dw.dim_department AS d ON d.department_key = c.current_department_key
JOIN dw.dim_department AS fd ON fd.department_key = c.former_department_key
WHERE (d.member_type = 'Unallocated' AND (c.method <> 'unallocated former department' OR d.department_number <> N'U' + fd.department_number))
   OR (c.method = 'unallocated former department' AND d.member_type <> 'Unallocated')
UNION ALL
-- an Unallocated member that nothing uses is dead
SELECT NULL, NULL, d.department_number, NULL, 'Unallocated member with no line'
FROM dw.dim_department AS d
WHERE d.member_type = 'Unallocated'
  AND NOT EXISTS (SELECT 1 FROM dw.current_structure_line AS c WHERE c.current_department_key = d.department_key)
UNION ALL
-- a line decided by an authored row may be placed in an Unallocated member only on purpose; none is today
SELECT c.organisation_key, c.sub_segment_code, d.department_number, NULL, 'authored line in an Unallocated member'
FROM dw.current_structure_line AS c
JOIN dw.dim_department AS d ON d.department_key = c.current_department_key
WHERE d.member_type = 'Unallocated' AND c.authored_row IS NOT NULL;
