-- Independent of the model's view: the synthetic table joined to the department dimension and the live flag.
SELECT u.user_principal_name, d.department_key
FROM synthetic.user_department AS u
JOIN dw.dim_department AS d ON d.department_number = u.department_number AND d.member_type = 'Department'
JOIN dw.current_structure_department AS c ON c.department_key = d.department_key AND c.is_live = 1
ORDER BY u.user_principal_name, d.department_key;
