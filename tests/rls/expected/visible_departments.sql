-- Independent of the model: the live departments of the current structure whose number the map gives the user.
SELECT d.department_number AS department_number, d.department_name AS department
FROM dw.dim_department AS d
JOIN dw.current_structure_department AS c ON c.department_key = d.department_key AND c.is_live = 1
WHERE d.member_type = 'Department'
  AND d.department_number IN (SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user})
ORDER BY d.department_number;
