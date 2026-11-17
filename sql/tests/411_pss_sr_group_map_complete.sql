-- test: every PSS Spending Review group name is matched to an OSCAR group (exactly, or through the three authored aliases) and the aliases hold no amounts
-- marker: localdata
-- requires: stg.pss_sr_group_map, authored.pss_sr_group_alias, stg.pss_outturn
SELECT N'PSS name not matched' AS problem, pss_sr_group_name AS detail
FROM stg.pss_sr_group_map WHERE match_method = 'unmatched' OR sr_group_name IS NULL
UNION ALL
SELECT N'alias matches <> 3', CAST(COUNT(*) AS nvarchar(200))
FROM stg.pss_sr_group_map WHERE match_method = 'alias' HAVING COUNT(*) <> 3
UNION ALL
SELECT N'alias target is not an OSCAR group', a.bud_sr_group_name
FROM authored.pss_sr_group_alias AS a
WHERE NOT EXISTS (SELECT 1 FROM stg.bud_department_group_map AS m
                  WHERE m.is_latest_vintage = 1 AND m.sr_group_name = a.bud_sr_group_name)
UNION ALL
SELECT N'two PSS names map to one OSCAR group', sr_group_name
FROM stg.pss_sr_group_map GROUP BY sr_group_name HAVING COUNT(*) > 1
UNION ALL
SELECT N'authored table has a numeric column (it must hold no amounts)', c.name
FROM sys.columns AS c
JOIN sys.types AS t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'authored.pss_sr_group_alias')
  AND t.name IN (N'int', N'bigint', N'smallint', N'tinyint', N'decimal', N'numeric', N'float', N'real', N'money', N'smallmoney')
UNION ALL
SELECT N'PSS rows lost between raw and stg', CAST(r.n AS nvarchar(30)) + N' vs ' + CAST(s.n AS nvarchar(30))
FROM (SELECT COUNT_BIG(*) AS n FROM raw.pss) AS r CROSS JOIN (SELECT COUNT_BIG(*) AS n FROM stg.pss_outturn) AS s
WHERE r.n <> s.n;
