-- test: every organisation version and sub-segment pair of the outturn has exactly one Spending Review group in dw.outturn_sr_group_bridge, none through an unknown department, none in a plan-side member (in particular not Unallocated central funds), and the regrouped lines add up to the fact
SELECT 'pair in the fact without a bridge row' AS problem, CAST(f.organisation_key AS nvarchar(20)) AS detail, sg.sub_segment_code AS detail2
FROM (SELECT DISTINCT organisation_key, segment_key FROM dw.fact_outturn) AS f
JOIN dw.dim_segment AS sg ON sg.segment_key = f.segment_key
WHERE NOT EXISTS (SELECT 1 FROM dw.outturn_sr_group_bridge AS b
                  WHERE b.organisation_key = f.organisation_key AND b.sub_segment_code = sg.sub_segment_code)
UNION ALL
SELECT 'pair with more than one bridge row', CAST(organisation_key AS nvarchar(20)), sub_segment_code
FROM dw.outturn_sr_group_bridge
GROUP BY organisation_key, sub_segment_code HAVING COUNT(*) <> 1
UNION ALL
SELECT 'bridge row without a group that exists', CAST(b.organisation_key AS nvarchar(20)), b.sub_segment_code
FROM dw.outturn_sr_group_bridge AS b
LEFT JOIN dw.dim_sr_group AS g ON g.sr_group_key = b.sr_group_key
WHERE g.sr_group_key IS NULL
UNION ALL
SELECT 'bridge row through an unknown department', CAST(organisation_key AS nvarchar(20)), sub_segment_code
FROM dw.outturn_sr_group_bridge WHERE bridge_rule = 'unknown department'
UNION ALL
SELECT 'bridge row in a group that is not a department group or the outturn-only member: ' + g.sr_group_name,
       CAST(b.organisation_key AS nvarchar(20)), b.sub_segment_code
FROM dw.outturn_sr_group_bridge AS b
JOIN dw.dim_sr_group AS g ON g.sr_group_key = b.sr_group_key
WHERE g.member_type NOT IN ('spending_review_group', 'outturn_only')
UNION ALL
SELECT 'outturn line in Unallocated central funds', CAST(COUNT(*) AS nvarchar(20)), NULL
FROM dw.outturn_plan_line AS l
JOIN dw.dim_sr_group AS g ON g.sr_group_key = l.sr_group_key
WHERE g.sr_group_code = 'NONDEPT_UNALLOC' OR g.sr_group_name = N'Unallocated central funds'
HAVING COUNT(*) > 0
UNION ALL
SELECT 'outturn line with no Spending Review group', CAST(COUNT(*) AS nvarchar(20)), NULL
FROM dw.outturn_plan_line AS l
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_sr_group AS g WHERE g.sr_group_key = l.sr_group_key)
HAVING COUNT(*) > 0
UNION ALL
SELECT 'bridge pair is not a pair of the structure map', CAST(b.organisation_key AS nvarchar(20)), b.sub_segment_code
FROM dw.outturn_sr_group_bridge AS b
WHERE NOT EXISTS (SELECT 1 FROM stg.current_structure_map AS m
                  WHERE m.organisation_key = b.organisation_key AND m.sub_segment_code = b.sub_segment_code
                    AND m.current_department_key = b.current_department_key)
UNION ALL
SELECT 'regrouped lines differ from dw.fact_outturn', CAST(SUM(l.amount_delta) AS nvarchar(40)), CAST((SELECT SUM(amount_delta) FROM dw.fact_outturn) AS nvarchar(40))
FROM dw.outturn_plan_line AS l
HAVING SUM(l.amount_delta) <> (SELECT SUM(amount_delta) FROM dw.fact_outturn)
UNION ALL
SELECT 'regrouped lines differ from dw.fact_outturn in release ' + r.label, CAST(x.a AS nvarchar(40)), CAST(y.a AS nvarchar(40))
FROM dw.dim_release AS r
CROSS APPLY (SELECT SUM(amount_delta) AS a FROM dw.outturn_plan_line WHERE release_key = r.release_key) AS x
CROSS APPLY (SELECT SUM(amount_delta) AS a FROM dw.fact_outturn WHERE release_key = r.release_key) AS y
WHERE ISNULL(x.a, 0) <> ISNULL(y.a, 0);
