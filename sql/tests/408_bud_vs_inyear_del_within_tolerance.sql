-- test: every one of the 15 year and vintage DEL pairs is within 3.5%, and AME, non-budget and total are boundary differences, never failures
-- marker: localdata
-- requires: audit.bud_vs_inyear_del
SELECT N'DEL pair outside tolerance or not pass' AS problem,
       CONCAT(financial_year, N' ', vintage, N' ', CAST(gap_share_of_bud AS nvarchar(20)), N' ', status) AS detail
FROM audit.bud_vs_inyear_del
WHERE level = 'DEL' AND (status <> 'pass' OR ABS(gap_share_of_bud) > 0.035 OR tolerance_share <> 0.035)
UNION ALL
SELECT N'DEL pairs <> 15', CAST(COUNT(*) AS nvarchar(20))
FROM audit.bud_vs_inyear_del WHERE level = 'DEL' HAVING COUNT(*) <> 15
UNION ALL
SELECT N'level other than DEL is not a boundary difference', CONCAT(financial_year, N' ', vintage, N' ', level)
FROM audit.bud_vs_inyear_del WHERE level <> 'DEL' AND status <> 'boundary difference'
UNION ALL
SELECT N'rows <> 60', CAST(COUNT(*) AS nvarchar(20))
FROM audit.bud_vs_inyear_del HAVING COUNT(*) <> 60
UNION ALL
SELECT N'TOTAL is not the sum of the levels', CONCAT(t.financial_year, N' ', t.vintage)
FROM audit.bud_vs_inyear_del AS t
JOIN (SELECT financial_year, vintage, SUM(inyear_amount) AS iy, SUM(bud_amount) AS bud
      FROM audit.bud_vs_inyear_del WHERE level <> 'TOTAL' GROUP BY financial_year, vintage) AS s
  ON s.financial_year = t.financial_year AND s.vintage = t.vintage
WHERE t.level = 'TOTAL' AND (t.inyear_amount <> s.iy OR t.bud_amount <> s.bud);
