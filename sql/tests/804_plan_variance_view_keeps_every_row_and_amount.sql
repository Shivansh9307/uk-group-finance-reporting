-- test: the plan variance view the model reads has the rows and the amounts of audit.plan_variance_reconciliation: no row added, dropped or recalculated
-- marker: localdata
-- requires: audit.plan_variance_reconciliation
SELECT 'plan variance view differs from the audit table' AS problem,
       CONCAT(v.n, ' ', v.p, ' ', v.o, ' against ', a.n, ' ', a.p, ' ', a.o) AS detail
FROM (SELECT COUNT_BIG(*) AS n, SUM(plan_amount) AS p, SUM(outturn) AS o FROM dw.v_model_plan_variance) AS v
CROSS JOIN (SELECT COUNT_BIG(*) AS n, SUM(plan_amount) AS p, SUM(outturn) AS o FROM audit.plan_variance_reconciliation) AS a
WHERE v.n <> a.n OR v.p <> a.p OR v.o <> a.o
UNION ALL
SELECT 'plan variance view differs in a verdict', CONCAT(v.financial_year, ' ', v.sr_group_name, ' ', v.measure)
FROM dw.v_model_plan_variance AS v
JOIN dw.dim_sr_group AS g ON g.sr_group_name = v.sr_group_name
JOIN audit.plan_variance_reconciliation AS a ON a.financial_year = v.financial_year AND a.sr_group_code = g.sr_group_code AND a.measure = v.measure
WHERE a.verdict <> v.verdict OR a.variance <> v.variance;
