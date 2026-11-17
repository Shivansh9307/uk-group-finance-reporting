-- test: dim_release matches stg.release, dim_scenario has the five scenarios, every sub-segment has one name per release, dim_control_budget has one control budget per detail code, the fact amount is DECIMAL(19,4), and the authored account table holds no amounts
SELECT 'dim_release differs from stg.release' AS problem, CAST(r.release_seq AS varchar(20)) AS detail
FROM stg.release AS r
LEFT JOIN dw.dim_release AS d ON d.release_key = r.release_seq AND d.label = r.release AND d.financial_year = r.financial_year
                             AND d.first_published = r.first_published AND d.highest_period = r.highest_period
WHERE d.release_key IS NULL
UNION ALL
SELECT 'dim_release flags', CAST(COUNT(*) AS varchar(20))
FROM dw.dim_release
HAVING SUM(CASE WHEN is_latest_release = 1 THEN 1 ELSE 0 END) <> 1
    OR SUM(CASE WHEN is_year_end_release = 1 THEN 1 ELSE 0 END) <> SUM(CASE WHEN highest_period = 12 THEN 1 ELSE 0 END)
    OR COUNT(*) <> (SELECT COUNT(*) FROM stg.release)
UNION ALL
SELECT 'dim_release: the year-end flag and the latest flag are not on the right rows', label
FROM dw.dim_release WHERE is_year_end_release <> (CASE WHEN highest_period = 12 THEN 1 ELSE 0 END)
   OR is_latest_release <> (CASE WHEN release_seq = (SELECT MAX(release_seq) FROM stg.release) THEN 1 ELSE 0 END)
UNION ALL
SELECT 'dim_scenario', CAST(COUNT(*) AS varchar(20))
FROM dw.dim_scenario
HAVING COUNT(*) <> 5
    OR SUM(CASE WHEN scenario_key = 1 AND scenario_name = N'Outturn' THEN 1 ELSE 0 END) <> 1
    OR SUM(CASE WHEN scenario_name IN (N'Outturn', N'Plan', N'Plan (phased)', N'Departments'' forecast', N'Own forecast') THEN 1 ELSE 0 END) <> 5
UNION ALL
SELECT 'a sub-segment has more than one name in one release in raw', r.release + ' ' + r.sub_segment_code
FROM raw.oscar_inyear AS r
GROUP BY r.release, r.sub_segment_code
HAVING COUNT(DISTINCT r.sub_segment_name) > 1
UNION ALL
SELECT 'a control budget detail code has more than one control budget', control_budget_detail_code
FROM dw.dim_control_budget WHERE control_budget_key <> -1 AND (control_budget IS NULL OR control_budget NOT IN ('DEL', 'AME', 'Non-budget'))
UNION ALL
SELECT 'dim_control_budget does not hold the five detail codes', CAST(COUNT(*) AS varchar(20))
FROM dw.dim_control_budget WHERE control_budget_key <> -1
HAVING COUNT(*) <> 5
UNION ALL
SELECT 'fact_outturn.amount_delta is not decimal(19,4)', ty.name + '(' + CAST(c.precision AS varchar(3)) + ',' + CAST(c.scale AS varchar(3)) + ')'
FROM sys.columns AS c JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'dw.fact_outturn') AND c.name = 'amount_delta' AND NOT (ty.name = 'decimal' AND c.precision = 19 AND c.scale = 4)
UNION ALL
SELECT 'fact_outturn has no clustered columnstore index', 'dw.fact_outturn'
FROM (VALUES (1)) AS one (x)
WHERE NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dw.fact_outturn') AND type_desc = 'CLUSTERED COLUMNSTORE')
UNION ALL
SELECT 'authored.account_flow has a column that could hold an amount', c.name
FROM sys.columns AS c WHERE c.object_id = OBJECT_ID(N'authored.account_flow')
  AND (c.name LIKE '%amount%' OR c.name LIKE '%value%' OR c.name LIKE '%total%');
