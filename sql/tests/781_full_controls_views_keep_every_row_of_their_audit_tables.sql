-- test: the annual-control, PSS-control and load-control views have the rows and the amounts of the audit tables they read (60, 443 and 46 rows in the real data); no row is added, dropped or recalculated
-- marker: localdata
-- requires: audit.bud_vs_inyear_del, audit.pss_vs_outturn, audit.bud_file_control
SELECT 'annual control view differs from audit.bud_vs_inyear_del' AS problem, CONCAT(v.n, ' ', v.s, ' against ', a.n, ' ', a.s) AS detail
FROM (SELECT COUNT_BIG(*) AS n, SUM(gap) AS s FROM dw.v_model_annual_control) AS v
CROSS JOIN (SELECT COUNT_BIG(*) AS n, SUM(gap) AS s FROM audit.bud_vs_inyear_del) AS a
WHERE v.n <> a.n OR v.s <> a.s
UNION ALL
SELECT 'pss control view differs from audit.pss_vs_outturn', CONCAT(v.n, ' ', v.s, ' against ', a.n, ' ', a.s)
FROM (SELECT COUNT_BIG(*) AS n, SUM(gap) AS s FROM dw.v_model_pss_control) AS v
CROSS JOIN (SELECT COUNT_BIG(*) AS n, SUM(gap) AS s FROM audit.pss_vs_outturn) AS a
WHERE v.n <> a.n OR v.s <> a.s
UNION ALL
SELECT 'load control view differs from the two file controls', CONCAT(v.n, ' ', v.r, ' against ', a.n, ' ', a.r)
FROM (SELECT COUNT_BIG(*) AS n, SUM(CAST(rows_loaded AS bigint)) AS r FROM dw.v_model_load_control) AS v
CROSS JOIN (
    SELECT (SELECT COUNT_BIG(*) FROM audit.file_control WHERE primary_for_release = 'Y') + (SELECT COUNT_BIG(*) FROM audit.bud_file_control) AS n,
           (SELECT SUM(CAST(rows_loaded AS bigint)) FROM audit.file_control WHERE primary_for_release = 'Y') + (SELECT SUM(CAST(rows_loaded AS bigint)) FROM audit.bud_file_control) AS r
) AS a
WHERE v.n <> a.n OR v.r <> a.r;
