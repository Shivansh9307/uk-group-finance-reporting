-- test: every account (economic category, and the Unknown member) maps to exactly one detail line of the statement, the line is the one the most specific matching rule names (resolved here a second way, with LIKE on the rule lists), and no two rules of the top specificity disagree
WITH ar AS (
    SELECT r.rule_id, l.line_key, r.specificity,
           N'|' + r.economic_budget + N'|' AS eb, r.flow,
           N'|' + r.pesa_economic_group_code + N'|' AS grp, N'|' + r.economic_category_code + N'|' AS cat,
           r.economic_budget AS eb_raw, r.pesa_economic_group_code AS grp_raw, r.economic_category_code AS cat_raw
    FROM stg.statement_account_rule AS r
    JOIN dw.statement_line AS l ON l.line_id = r.line_id
), hit AS (
    SELECT a.account_key, ar.rule_id, ar.line_key, ar.specificity
    FROM dw.dim_account AS a
    JOIN ar ON (ar.eb_raw = N'' OR ar.eb LIKE N'%|' + a.economic_budget + N'|%')
           AND (ar.flow = '' OR ar.flow = a.flow)
           AND (ar.grp_raw = N'' OR CHARINDEX(N'|' + a.pesa_economic_group_code + N'|', ar.grp) > 0)
           AND (ar.cat_raw = N'' OR ar.cat LIKE N'%|' + a.economic_category_code + N'|%')
), top_rule AS (
    SELECT account_key, MAX(specificity) AS s FROM hit GROUP BY account_key
)
SELECT 'account with no line' AS problem, CAST(a.account_key AS nvarchar(20)) AS detail
FROM dw.dim_account AS a
WHERE NOT EXISTS (SELECT 1 FROM dw.account_statement_line AS m WHERE m.account_key = a.account_key)
UNION ALL
SELECT 'account with more than one row', CAST(account_key AS nvarchar(20))
FROM dw.account_statement_line GROUP BY account_key HAVING COUNT(*) > 1
UNION ALL
SELECT 'mapped line is not a detail line', CAST(m.account_key AS nvarchar(20))
FROM dw.account_statement_line AS m
JOIN dw.statement_line AS l ON l.line_key = m.line_key
WHERE l.line_type <> 'detail'
UNION ALL
SELECT 'two rules of the top specificity name different lines', CAST(h.account_key AS nvarchar(20))
FROM hit AS h JOIN top_rule AS t ON t.account_key = h.account_key AND t.s = h.specificity
GROUP BY h.account_key HAVING COUNT(DISTINCT h.line_key) > 1
UNION ALL
SELECT 'mapped line differs from the most specific rule', CAST(m.account_key AS nvarchar(20))
FROM dw.account_statement_line AS m
JOIN top_rule AS t ON t.account_key = m.account_key
WHERE NOT EXISTS (SELECT 1 FROM hit AS h WHERE h.account_key = m.account_key AND h.specificity = t.s AND h.line_key = m.line_key)
UNION ALL
SELECT 'a detail line has no account', l.line_id
FROM dw.statement_line AS l
WHERE l.line_type = 'detail' AND NOT EXISTS (SELECT 1 FROM dw.account_statement_line AS m WHERE m.line_key = l.line_key);
