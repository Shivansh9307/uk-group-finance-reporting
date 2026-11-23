-- test: the file-control view has one row for each of the 31 primary release files and the file totals of the audit table, and the plan-coverage view has the rows and totals of dw.plan_coverage; neither adds, drops or changes a number
SELECT 'file control view rows differ from the primary release files' AS problem,
       CONCAT(v.n, ' against ', a.n) AS detail
FROM (SELECT COUNT_BIG(*) AS n, SUM(file_total_4dp) AS s FROM dw.v_model_file_control) AS v
CROSS JOIN (SELECT COUNT_BIG(*) AS n, SUM(CAST(amount_sum_4dp_expected AS decimal(38, 4))) AS s FROM audit.file_control WHERE primary_for_release = 'Y') AS a
WHERE v.n <> a.n OR v.s <> a.s
UNION ALL
SELECT 'file control view does not resolve every release', CAST(COUNT(*) AS varchar(20))
FROM dw.v_model_file_control AS v
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_release AS r WHERE r.release_key = v.release_key)
HAVING COUNT(*) > 0
UNION ALL
SELECT 'file control view has not one row per release', CAST(COUNT(*) AS varchar(20))
FROM (SELECT release_key FROM dw.v_model_file_control GROUP BY release_key HAVING COUNT(*) <> 1) AS d
HAVING COUNT(*) > 0
UNION ALL
SELECT 'plan coverage view rows or total differ from dw.plan_coverage', CONCAT(v.n, ' ', v.s, ' against ', a.n, ' ', a.s)
FROM (SELECT COUNT_BIG(*) AS n, SUM(amount_total) AS s FROM dw.v_model_plan_coverage) AS v
CROSS JOIN (SELECT COUNT_BIG(*) AS n, SUM(amount_total) AS s FROM dw.plan_coverage) AS a
WHERE v.n <> a.n OR v.s <> a.s;
