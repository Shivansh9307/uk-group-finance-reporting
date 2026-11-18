-- test: every department number an outturn line was reported under maps to exactly one live department of the current structure, so the as-reported structure added over the departments adds back to the total; the numbers that no live Department carries are the four closed ones and nothing else; the view lists each number once
SELECT 'a reported number has no mapping' AS problem, x.department_number AS detail
FROM (SELECT DISTINCT d.department_number
      FROM dw.fact_outturn AS f
      JOIN dw.dim_organisation AS o ON o.organisation_key = f.organisation_key
      JOIN dw.dim_department AS d ON d.department_key = o.department_key) AS x
WHERE NOT EXISTS (SELECT 1 FROM dw.department_reported_number AS m WHERE m.reported_department_number = x.department_number)
UNION ALL
SELECT 'a mapping points at a department that is not live', m.reported_department_number
FROM dw.department_reported_number AS m
WHERE NOT EXISTS (SELECT 1 FROM dw.current_structure_department AS c WHERE c.department_key = m.current_department_key AND c.is_live = 1)
UNION ALL
SELECT 'the mapped amount differs from the fact', CAST(a.v AS nvarchar(40)) + N' against ' + CAST(b.v AS nvarchar(40))
FROM (SELECT SUM(reported_net_amount) AS v FROM dw.department_reported_number) AS a
CROSS JOIN (SELECT SUM(amount_delta) AS v FROM dw.fact_outturn) AS b
WHERE a.v <> b.v
UNION ALL
SELECT 'a number is not mapped by its own rule although a live department carries it', m.reported_department_number
FROM dw.department_reported_number AS m
JOIN dw.dim_department AS d ON d.department_number = m.reported_department_number AND d.member_type = 'Department'
JOIN dw.current_structure_department AS c ON c.department_key = d.department_key AND c.is_live = 1
WHERE m.mapping_rule <> 'own number' OR m.current_department_key <> d.department_key
UNION ALL
SELECT 'the numbers without an own department are not the four closed ones',
       STRING_AGG(m.reported_department_number, N',') WITHIN GROUP (ORDER BY m.reported_department_number)
FROM dw.department_reported_number AS m
WHERE m.mapping_rule <> 'own number'
HAVING STRING_AGG(m.reported_department_number, N',') WITHIN GROUP (ORDER BY m.reported_department_number) <> N'011,027,035,077'
UNION ALL
SELECT 'the Foreign and Commonwealth Office is not folded into the Foreign, Commonwealth and Development Office', m.reported_department_number
FROM dw.department_reported_number AS m
JOIN dw.dim_department AS d ON d.department_key = m.current_department_key
WHERE m.reported_department_number = N'027' AND NOT (d.department_number = N'030' AND m.mapping_rule = 'largest receiver')
UNION ALL
SELECT 'the view lists a number for two departments or lists a number that is not mapped', t.n
FROM (SELECT x.value AS n, COUNT(*) AS k
      FROM dw.v_model_department AS v
      CROSS APPLY STRING_SPLIT(v.reported_department_numbers, N'|') AS x
      WHERE x.value <> N''
      GROUP BY x.value) AS t
WHERE t.k > 1 OR NOT EXISTS (SELECT 1 FROM dw.department_reported_number AS m WHERE m.reported_department_number = t.n)
UNION ALL
SELECT 'the view lists a different number of numbers than the table holds', CAST(a.n AS nvarchar(20)) + N' against ' + CAST(b.n AS nvarchar(20))
FROM (SELECT COUNT(*) AS n FROM dw.v_model_department AS v
      CROSS APPLY STRING_SPLIT(v.reported_department_numbers, N'|') AS x WHERE x.value <> N'') AS a
CROSS JOIN (SELECT COUNT(*) AS n FROM dw.department_reported_number) AS b
WHERE a.n <> b.n;
