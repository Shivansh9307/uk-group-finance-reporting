-- test: the user map is synthetic (description, class, reserved domain), every row names a live department of the current structure, no row repeats, the model view keeps every row, and the map holds the three cases the roles are tested with: a user with two or more departments, a user whose department has outturn in fewer years than the data has, and a user who is in no row
SELECT 'description does not say SYNTHETIC' AS problem, 'synthetic.user_department' AS detail
WHERE NOT EXISTS (SELECT 1 FROM sys.extended_properties AS p
                  WHERE p.class = 1 AND p.major_id = OBJECT_ID('synthetic.user_department') AND p.minor_id = 0
                    AND p.name = N'MS_Description' AND CAST(p.value AS nvarchar(max)) LIKE N'SYNTHETIC%')
UNION ALL
SELECT 'a row is not synthetic or not in the reserved domain', user_principal_name
FROM synthetic.user_department
WHERE data_class <> 'synthetic' OR user_principal_name NOT LIKE N'%@example.org'
UNION ALL
SELECT 'a department number is not a live department of the current structure', u.user_principal_name + ' -> ' + u.department_number
FROM synthetic.user_department AS u
WHERE NOT EXISTS (SELECT 1
                  FROM dw.dim_department AS d
                  JOIN dw.current_structure_department AS c ON c.department_key = d.department_key AND c.is_live = 1
                  WHERE d.department_number = u.department_number AND d.member_type = 'Department')
UNION ALL
SELECT 'the model view drops or repeats a row of the map',
       'rows in the map ' + CAST((SELECT COUNT(*) FROM synthetic.user_department) AS varchar(10))
       + ', rows in the view ' + CAST((SELECT COUNT(*) FROM dw.v_model_user_department) AS varchar(10))
WHERE (SELECT COUNT(*) FROM synthetic.user_department) <> (SELECT COUNT(*) FROM dw.v_model_user_department)
UNION ALL
SELECT 'no user has two or more departments', ''
WHERE NOT EXISTS (SELECT 1 FROM synthetic.user_department GROUP BY user_principal_name HAVING COUNT(*) >= 2)
UNION ALL
SELECT 'no user is mapped to a department with outturn in fewer years than the data has', ''
WHERE NOT EXISTS (
    SELECT 1
    FROM synthetic.user_department AS u
    JOIN dw.dim_department AS d ON d.department_number = u.department_number AND d.member_type = 'Department'
    JOIN dw.current_structure_department AS c ON c.department_key = d.department_key AND c.is_live = 1
    WHERE (SELECT COUNT(DISTINCT p.financial_year)
           FROM dw.fact_outturn AS f JOIN dw.dim_period AS p ON p.period_key = f.period_key
           WHERE f.current_department_key = d.department_key)
        < (SELECT COUNT(DISTINCT p.financial_year) FROM dw.fact_outturn AS f JOIN dw.dim_period AS p ON p.period_key = f.period_key))
UNION ALL
SELECT 'the user that the tests use as unmapped is in the map', user_principal_name
FROM synthetic.user_department WHERE user_principal_name = N'nobody@example.org'
UNION ALL
SELECT 'the unmapped user has rows in a view', 'dw.v_model_user_department'
WHERE EXISTS (SELECT 1 FROM dw.v_model_user_department WHERE user_principal_name = N'nobody@example.org')
UNION ALL
SELECT 'the unmapped user has rows in a view', 'dw.v_model_user_plan_group'
WHERE EXISTS (SELECT 1 FROM dw.v_model_user_plan_group WHERE user_principal_name = N'nobody@example.org');
