-- test: a line with plan scope RESOURCE or CAPITAL adds up exactly the accounts whose economic budget is that budget, and the line with scope ALL adds up every account, so the plan that the source publishes at that level is compared with the same accounts
WITH members AS (
    SELECT l.line_id, l.plan_scope, a.account_key, a.economic_budget
    FROM dw.statement_line AS l
    JOIN dw.statement_line_member AS m ON m.line_key = l.line_key
    JOIN dw.account_statement_line AS s ON s.line_key = m.detail_line_key
    JOIN dw.dim_account AS a ON a.account_key = s.account_key
    WHERE l.plan_scope <> ''
)
SELECT 'account in the line that is not in the budget' AS problem, line_id AS detail, CAST(account_key AS nvarchar(20)) AS detail2
FROM members WHERE plan_scope IN ('RESOURCE', 'CAPITAL') AND economic_budget <> plan_scope
UNION ALL
SELECT 'account of the budget that is not in the line', l.line_id, CAST(a.account_key AS nvarchar(20))
FROM dw.statement_line AS l
JOIN dw.dim_account AS a ON a.economic_budget = l.plan_scope
WHERE l.plan_scope IN ('RESOURCE', 'CAPITAL')
  AND NOT EXISTS (SELECT 1 FROM members AS m WHERE m.line_id = l.line_id AND m.account_key = a.account_key)
UNION ALL
SELECT 'scope ALL does not hold every account once', l.line_id, CAST(a.account_key AS nvarchar(20))
FROM dw.statement_line AS l
CROSS JOIN dw.dim_account AS a
WHERE l.plan_scope = 'ALL'
  AND (SELECT COUNT(*) FROM members AS m WHERE m.line_id = l.line_id AND m.account_key = a.account_key) <> 1
UNION ALL
SELECT 'no line has plan scope ' + s.scope, s.scope, ''
FROM (VALUES ('RESOURCE'), ('CAPITAL'), ('ALL')) AS s(scope)
WHERE NOT EXISTS (SELECT 1 FROM dw.statement_line AS l WHERE l.plan_scope = s.scope);
