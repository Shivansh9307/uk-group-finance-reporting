-- test: a line carries one department in all its releases, and current_department_key is what stg.current_structure_map gives for the organisation version and sub-segment
SELECT 'line with more than one department' AS problem, f.organisation_key, f.segment_key, f.account_key, f.control_budget_key, f.period_key, COUNT(DISTINCT f.department_key) AS n
FROM dw.fact_outturn AS f
GROUP BY f.organisation_key, f.segment_key, f.account_key, f.control_budget_key, f.period_key
HAVING COUNT(DISTINCT f.department_key) > 1
UNION ALL
SELECT 'current department differs from the map', f.organisation_key, f.segment_key, NULL, NULL, NULL, COUNT(*)
FROM dw.fact_outturn AS f
JOIN dw.dim_segment AS sg ON sg.segment_key = f.segment_key
LEFT JOIN stg.current_structure_map AS m ON m.organisation_key = f.organisation_key AND m.sub_segment_code = sg.sub_segment_code
WHERE f.current_department_key <> ISNULL(m.current_department_key, -1)
GROUP BY f.organisation_key, f.segment_key
UNION ALL
SELECT 'department differs from the release map', f.organisation_key, f.segment_key, NULL, NULL, NULL, COUNT(*)
FROM dw.fact_outturn AS f
WHERE f.revision_no = 0 AND NOT EXISTS (
    SELECT 1
    FROM stg.inyear_snapshot AS s
    JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
    JOIN dw.dim_release AS r ON r.label = s.release
    JOIN dw.dim_segment AS sg ON sg.sub_segment_code = s.sub_segment_code
    WHERE m.organisation_key = f.organisation_key AND m.department_key = f.department_key AND sg.segment_key = f.segment_key
      AND CAST(LEFT(s.financial_year, 4) AS int) * 100 + s.period = f.period_key)
GROUP BY f.organisation_key, f.segment_key;
