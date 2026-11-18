-- test: the model's outturn view carries the estimated flag of the line's row in the current-structure map for every row, the three estimated lines are the ones the authored file marks, and no other row is flagged
SELECT 'a fact row has a different estimated flag from its line' AS problem, CAST(COUNT_BIG(*) AS nvarchar(20)) AS detail
FROM dw.v_model_fact_outturn AS v
JOIN dw.dim_segment AS s ON s.segment_key = v.segment_key
JOIN dw.current_structure_line AS l ON l.organisation_key = v.organisation_key AND l.sub_segment_code = s.sub_segment_code
WHERE v.mapping_is_estimated <> l.is_estimated
HAVING COUNT_BIG(*) > 0
UNION ALL
SELECT 'the estimated lines are not the three authored ones', STRING_AGG(l.sub_segment_code, N',') WITHIN GROUP (ORDER BY l.sub_segment_code)
FROM dw.current_structure_line AS l WHERE l.is_estimated = 1
HAVING STRING_AGG(l.sub_segment_code, N',') WITHIN GROUP (ORDER BY l.sub_segment_code) <> N'X084A031,X084A254,X084A364'
UNION ALL
SELECT 'a fact row has no line in the current-structure map', CAST(COUNT_BIG(*) AS nvarchar(20))
FROM dw.v_model_fact_outturn AS v
JOIN dw.dim_segment AS s ON s.segment_key = v.segment_key
WHERE NOT EXISTS (SELECT 1 FROM dw.current_structure_line AS l WHERE l.organisation_key = v.organisation_key AND l.sub_segment_code = s.sub_segment_code)
HAVING COUNT_BIG(*) > 0
UNION ALL
SELECT 'an estimated line has no fact row', l.sub_segment_code
FROM dw.current_structure_line AS l
WHERE l.is_estimated = 1
  AND NOT EXISTS (SELECT 1 FROM dw.v_model_fact_outturn AS v JOIN dw.dim_segment AS s ON s.segment_key = v.segment_key
                  WHERE v.organisation_key = l.organisation_key AND s.sub_segment_code = l.sub_segment_code AND v.mapping_is_estimated = 1);
