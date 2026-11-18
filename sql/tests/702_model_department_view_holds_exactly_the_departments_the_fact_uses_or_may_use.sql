-- test: the current-structure department view holds every department the outturn fact points at, only live members, each department number at most once, and the Unknown member is not in it
SELECT 'fact points at a department outside the view' AS problem, CAST(f.current_department_key AS nvarchar(20)) AS detail
FROM (SELECT DISTINCT current_department_key FROM dw.fact_outturn) AS f
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_department AS d WHERE d.department_key = f.current_department_key)
UNION ALL
SELECT 'view member is not live', CAST(d.department_key AS nvarchar(20))
FROM dw.v_model_department AS d
JOIN dw.current_structure_department AS c ON c.department_key = d.department_key
WHERE c.is_live = 0
UNION ALL
SELECT 'department number twice in the view', d.department_number
FROM dw.v_model_department AS d
GROUP BY d.department_number HAVING COUNT(*) > 1
UNION ALL
SELECT 'Unknown member in the view', CAST(d.department_key AS nvarchar(20))
FROM dw.v_model_department AS d WHERE d.department_key = -1 OR d.member_type = 'Unknown';
