-- Independent of the model: the rows of the synthetic table that belong to the user, with the key of the department.
SELECT u.user_principal_name, d.department_key
FROM synthetic.user_department AS u
JOIN dw.dim_department AS d ON d.department_number = u.department_number AND d.member_type = 'Department'
JOIN dw.current_structure_department AS c ON c.department_key = d.department_key AND c.is_live = 1
WHERE u.user_principal_name = {user}
ORDER BY u.user_principal_name, d.department_key;
