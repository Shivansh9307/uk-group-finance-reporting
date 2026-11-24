-- test: authored.tac_code_map is true to the forms and the data: a retired code is in no form after its last year and in no data after it, and a relabelled code is in the latest form with a different label before and after the change year
-- marker: localdata
SELECT m.old_sub_code, 'retired code appears in a later form or later data' AS problem
FROM stg.tac_code_map AS m
WHERE m.change_kind = 'retired'
  AND (EXISTS (SELECT 1 FROM stg.tac_template_line AS t WHERE t.sub_code = m.old_sub_code AND t.release > m.last_year_old)
       OR EXISTS (SELECT 1 FROM stg.tac_value AS v WHERE v.sub_code = m.old_sub_code AND v.release > m.last_year_old))
UNION ALL
SELECT m.old_sub_code, 'retired code is not in the form of its last year'
FROM stg.tac_code_map AS m
WHERE m.change_kind = 'retired'
  AND NOT EXISTS (SELECT 1 FROM stg.tac_template_line AS t WHERE t.sub_code = m.old_sub_code AND t.release = m.last_year_old)
UNION ALL
SELECT m.old_sub_code, 'relabelled code does not change its label at the stated year'
FROM stg.tac_code_map AS m
WHERE m.change_kind = 'relabelled'
  AND (SELECT MAX(t.label) FROM stg.tac_template_line AS t WHERE t.sub_code = m.old_sub_code AND t.release = m.last_year_old)
    = (SELECT MAX(t.label) FROM stg.tac_template_line AS t WHERE t.sub_code = m.old_sub_code AND t.release = m.first_year_new)
UNION ALL
SELECT sub_code, 'a line changed its label between forms and the code map does not say so'
FROM dw.tac_statutory_line AS l
WHERE l.description_variants > 1
  AND NOT EXISTS (SELECT 1 FROM stg.tac_code_map AS m WHERE m.old_sub_code = l.sub_code)
  AND l.sub_code NOT IN (SELECT sub_code FROM (SELECT sub_code, COUNT(DISTINCT UPPER(REPLACE(label, ' ', ''))) AS n
                                               FROM stg.tac_template_line WHERE sub_code <> '' GROUP BY sub_code) AS q WHERE n = 1);
