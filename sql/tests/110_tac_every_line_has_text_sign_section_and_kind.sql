-- test: dw.tac_statutory_line has one row per code of the illustrative forms and of the data; the authored role file covers exactly those codes; a label that starts with Total is a subtotal or total; a section is one contiguous block of the form; the sub code belongs to one statement only; the sign is one of the three the form uses
-- marker: localdata
SELECT t.sub_code, t.statement, 'form code with no line' AS problem
FROM (SELECT DISTINCT sub_code, statement FROM stg.tac_template_line WHERE sub_code <> '') AS t
LEFT JOIN dw.tac_statutory_line AS l ON l.sub_code = t.sub_code AND l.statement = t.statement
WHERE l.line_key IS NULL
UNION ALL
SELECT r.sub_code, r.statement, 'role row for a code that is in no form'
FROM stg.tac_line_role AS r
WHERE NOT EXISTS (SELECT 1 FROM stg.tac_template_line AS t WHERE t.sub_code = r.sub_code AND t.statement = r.statement)
UNION ALL
SELECT sub_code, NULL, 'sub code in more than one statement of the forms'
FROM stg.tac_template_line WHERE sub_code <> '' GROUP BY sub_code HAVING COUNT(DISTINCT statement) > 1
UNION ALL
SELECT DISTINCT v.sub_code, v.statement, 'value code with no line'
FROM stg.tac_value AS v
LEFT JOIN dw.tac_statutory_line AS l ON l.sub_code = v.sub_code AND l.statement = v.statement
WHERE l.line_key IS NULL
UNION ALL
SELECT sub_code, statement, 'a Total line is not a subtotal or total'
FROM dw.tac_statutory_line WHERE description LIKE 'Total %' AND line_kind = 'line'
UNION ALL
SELECT sub_code, statement, 'sign is not one the form uses'
FROM dw.tac_statutory_line WHERE expected_sign NOT IN ('+', '-', '+/-')
UNION ALL
SELECT NULL, statement, 'a section is split into more than one block of the form (' + section + ')'
FROM (SELECT statement, table_id, section,
             ROW_NUMBER() OVER (PARTITION BY statement, table_id ORDER BY form_row) -
             ROW_NUMBER() OVER (PARTITION BY statement, table_id, section ORDER BY form_row) AS grp
      FROM dw.tac_statutory_line) AS x
GROUP BY statement, table_id, section
HAVING COUNT(DISTINCT grp) > 1;
