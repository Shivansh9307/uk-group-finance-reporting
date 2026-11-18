-- test: the hold-out table adds up to the totals of audit.bud_vs_inyear_del for the 2025-11 vintage (DEL and total), covers every year the vintage holds, and every BUD department group has a mapping row
-- marker: localdata
-- requires: audit.current_structure_holdout, audit.bud_vs_inyear_del, dw.bud_group_current_department
WITH h AS (
    SELECT financial_year, level, SUM(inyear_amount) AS inyear_amount, SUM(bud_amount) AS bud_amount, COUNT(*) AS n
    FROM audit.current_structure_holdout
    GROUP BY financial_year, level
)
SELECT c.financial_year, c.level, N'totals differ from audit.bud_vs_inyear_del' AS problem,
       CONCAT(h.inyear_amount, N' / ', c.inyear_amount, N' ; ', h.bud_amount, N' / ', c.bud_amount) AS detail
FROM audit.bud_vs_inyear_del AS c
LEFT JOIN h ON h.financial_year = c.financial_year AND h.level = c.level
WHERE c.vintage = N'2025-11' AND c.level IN (N'DEL', N'TOTAL')
  AND (h.financial_year IS NULL OR h.inyear_amount <> c.inyear_amount OR h.bud_amount <> c.bud_amount)
UNION ALL
SELECT NULL, NULL, N'BUD department group without a mapping row', g.department_group_code
FROM (SELECT DISTINCT department_group_code FROM stg.bud_department_group_map) AS g
WHERE NOT EXISTS (SELECT 1 FROM dw.bud_group_current_department m WHERE m.department_group_code = g.department_group_code);
