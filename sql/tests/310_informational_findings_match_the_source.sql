-- test: rule b is September 2022 only and covers every row of the release, rule c is the Period 0 rows of June 2019 only and matches raw, rule d is the one authored coding error
SELECT 'rule b: wrong releases' AS problem, STRING_AGG(release_from, ',') AS detail
FROM dw.dq_issue WHERE issue_rule = 'b'
HAVING STRING_AGG(release_from, ',') <> '2022-09' OR COUNT(*) <> 1
UNION ALL
SELECT 'rule b: rows differ from the rows of the release in raw', CAST(i.rows_affected AS varchar(20)) + ' vs ' + CAST(c.n AS varchar(20))
FROM dw.dq_issue AS i
CROSS APPLY (SELECT COUNT(*) AS n FROM raw.oscar_inyear AS r WHERE r.release = i.release_from AND r.[month] NOT LIKE 'Period 0%') AS c
WHERE i.issue_rule = 'b' AND i.rows_affected <> c.n
UNION ALL
SELECT 'rule c: wrong releases', STRING_AGG(release_from, ',')
FROM dw.dq_issue WHERE issue_rule = 'c'
HAVING STRING_AGG(release_from, ',') <> '2019-06' OR COUNT(*) <> 1
UNION ALL
SELECT 'rule c: rows differ from the Period 0 rows of the release in raw', CAST(i.rows_affected AS varchar(20)) + ' vs ' + CAST(c.n AS varchar(20))
FROM dw.dq_issue AS i
CROSS APPLY (SELECT COUNT(*) AS n FROM raw.oscar_inyear AS r WHERE r.release = i.release_from AND r.[month] LIKE 'Period 0%'
             AND NOT (r.amount_whole = 0 AND r.amount_frac = 0)) AS c
WHERE i.issue_rule = 'c' AND i.rows_affected <> c.n
UNION ALL
SELECT 'rule d: findings differ from the authored coding errors', CAST(COUNT(*) AS varchar(20))
FROM dw.dq_issue WHERE issue_rule = 'd'
HAVING COUNT(*) <> (SELECT COUNT(*) FROM authored.organisation_key_override WHERE reason = 'coding_error')
UNION ALL
SELECT 'rule d: code not in the authored coding errors', i.organisation_code
FROM dw.dq_issue AS i
WHERE i.issue_rule = 'd' AND NOT EXISTS (SELECT 1 FROM authored.organisation_key_override AS a WHERE a.reason = 'coding_error' AND a.organisation_code = i.organisation_code)
UNION ALL
SELECT 'finding ids are not 1..n', CAST(COUNT(*) AS varchar(20))
FROM dw.dq_issue HAVING MIN(dq_issue_id) <> 1 OR MAX(dq_issue_id) <> COUNT(*);
