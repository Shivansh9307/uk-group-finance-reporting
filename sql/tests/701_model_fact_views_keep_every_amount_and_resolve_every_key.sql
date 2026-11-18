-- test: the three model fact views carry the same total as their base fact, every outturn line keeps one Spending Review group and one data-quality key, and every plan row has the Plan scenario
SELECT 'outturn amount differs' AS problem, CAST(a.v AS nvarchar(60)) AS got, CAST(b.v AS nvarchar(60)) AS expected
FROM (SELECT SUM(CAST(amount_delta AS decimal(38, 4))) AS v FROM dw.v_model_fact_outturn) AS a
CROSS JOIN (SELECT SUM(CAST(amount_delta AS decimal(38, 4))) AS v FROM dw.fact_outturn) AS b
WHERE a.v <> b.v
UNION ALL
SELECT 'plan amount differs', CAST(a.v AS nvarchar(60)), CAST(b.v AS nvarchar(60))
FROM (SELECT SUM(CAST(amount AS decimal(38, 4))) AS v FROM dw.v_model_fact_plan) AS a
CROSS JOIN (SELECT SUM(CAST(amount AS decimal(38, 4))) AS v FROM dw.fact_plan) AS b
WHERE a.v <> b.v
UNION ALL
SELECT 'phased plan amount differs', CAST(a.v AS nvarchar(60)), CAST(b.v AS nvarchar(60))
FROM (SELECT SUM(CAST(amount AS decimal(38, 4))) AS v FROM dw.v_model_fact_plan_phased) AS a
CROSS JOIN (SELECT SUM(CAST(amount AS decimal(38, 4))) AS v FROM dw.fact_plan_phased) AS b
WHERE a.v <> b.v
UNION ALL
SELECT 'outturn line without a Spending Review group', CAST(COUNT_BIG(*) AS nvarchar(60)), '0'
FROM dw.v_model_fact_outturn AS f
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_sr_group AS g WHERE g.sr_group_key = f.sr_group_key)
HAVING COUNT_BIG(*) > 0
UNION ALL
SELECT 'outturn line whose data-quality key does not exist', CAST(COUNT_BIG(*) AS nvarchar(60)), '0'
FROM dw.v_model_fact_outturn AS f
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_data_quality AS q WHERE q.dq_issue_key = f.dq_issue_key)
HAVING COUNT_BIG(*) > 0
UNION ALL
SELECT 'flagged outturn rows differ from dw.fact_outturn', CAST(a.n AS nvarchar(60)), CAST(b.n AS nvarchar(60))
FROM (SELECT COUNT_BIG(*) AS n FROM dw.v_model_fact_outturn WHERE dq_issue_key <> 0) AS a
CROSS JOIN (SELECT COUNT_BIG(*) AS n FROM dw.fact_outturn WHERE dq_issue_id IS NOT NULL) AS b
WHERE a.n <> b.n
UNION ALL
SELECT 'plan row not in the Plan scenario', CAST(COUNT_BIG(*) AS nvarchar(60)), '0'
FROM dw.v_model_fact_plan AS p JOIN dw.dim_scenario AS s ON s.scenario_key = p.scenario_key
WHERE s.scenario_name <> N'Plan'
HAVING COUNT_BIG(*) > 0;
