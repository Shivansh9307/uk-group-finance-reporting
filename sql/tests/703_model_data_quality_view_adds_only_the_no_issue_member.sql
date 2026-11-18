-- test: the data-quality view is dw.dq_issue row for row plus one member with key 0 that holds no amount and flags no fact row, and key 0 is not an issue id
SELECT 'view lacks a finding' AS problem, CAST(i.dq_issue_id AS nvarchar(20)) AS detail
FROM dw.dq_issue AS i
WHERE NOT EXISTS (SELECT 1 FROM dw.v_model_data_quality AS q
                  WHERE q.dq_issue_key = i.dq_issue_id AND q.issue_rule = i.issue_rule
                    AND q.issue_type = i.issue_type AND q.rows_affected = i.rows_affected
                    AND q.flags_fact_rows = i.flags_fact_rows)
UNION ALL
SELECT 'a finding has the id of the added member', CAST(i.dq_issue_id AS nvarchar(20)) FROM dw.dq_issue AS i WHERE i.dq_issue_id = 0
UNION ALL
SELECT 'the added member holds an amount or flags rows', CAST(q.dq_issue_key AS nvarchar(20))
FROM dw.v_model_data_quality AS q
WHERE q.dq_issue_key = 0 AND (q.flags_fact_rows <> 0 OR q.amount_before IS NOT NULL OR q.amount_after IS NOT NULL OR q.rows_affected <> 0)
UNION ALL
SELECT 'the view does not have exactly one added member', CAST(COUNT(*) AS nvarchar(20))
FROM dw.v_model_data_quality AS q WHERE q.dq_issue_key = 0
HAVING COUNT(*) <> 1;
