-- test: the offsetting line of the NHS Pension Scheme unit error is flagged with it. For every unit error on line X903A002 there is an 'offsetting line' finding on line X903A003 in the same release pair, organisation, period, economic category and control budget whose change is the opposite of the first line's change within one per cent; the fact rows flagged for the two lines carry the same release, period and opposite signs within one per cent of each other; and there are thirteen flagged fact rows, six on the unit-error line and seven on its offsetting line (the offsetting line also has a small revision in December 2025 between the row that set the amount and the row that corrected it). Before the rule flagged the offsetting line, this test pinned the opposite (six flagged rows and an unflagged mirror for each).
SELECT 'a unit error has no offsetting-line finding in the same pair and month' AS problem, CAST(u.dq_issue_id AS nvarchar(10)) AS detail
FROM dw.dq_issue AS u
WHERE u.issue_rule = 'a' AND u.issue_type = 'unit error'
  AND NOT EXISTS (
      SELECT 1 FROM dw.dq_issue AS m
      WHERE m.issue_rule = 'a' AND m.issue_type = 'unit error (offsetting line)'
        AND m.release_from = u.release_from AND m.release_to = u.release_to AND m.organisation_key = u.organisation_key
        AND m.period_key = u.period_key AND m.account_key = u.account_key AND m.control_budget_key = u.control_budget_key
        AND m.sub_segment_code = N'X903A003'
        AND ABS((m.amount_after - m.amount_before) + (u.amount_after - u.amount_before)) <= 0.01 * ABS(u.amount_after - u.amount_before))
UNION ALL
SELECT 'an offsetting-line finding has no unit error to offset', CAST(m.dq_issue_id AS nvarchar(10))
FROM dw.dq_issue AS m
WHERE m.issue_rule = 'a' AND m.issue_type = 'unit error (offsetting line)'
  AND NOT EXISTS (
      SELECT 1 FROM dw.dq_issue AS u
      WHERE u.issue_rule = 'a' AND u.issue_type = 'unit error'
        AND m.release_from = u.release_from AND m.release_to = u.release_to AND m.organisation_key = u.organisation_key
        AND m.period_key = u.period_key AND m.account_key = u.account_key AND m.control_budget_key = u.control_budget_key)
UNION ALL
SELECT 'a flagged row of a unit error has no flagged row of the offsetting line', CAST(f.release_key AS nvarchar(10)) + N' ' + CAST(f.period_key AS nvarchar(10))
FROM dw.fact_outturn AS f
JOIN dw.dq_issue AS i ON i.dq_issue_id = f.dq_issue_id AND i.issue_type = 'unit error'
WHERE NOT EXISTS (
      SELECT 1
      FROM dw.fact_outturn AS g
      JOIN dw.dq_issue AS j ON j.dq_issue_id = g.dq_issue_id AND j.issue_type = 'unit error (offsetting line)'
      JOIN dw.dim_segment AS sg ON sg.segment_key = g.segment_key
      WHERE g.release_key = f.release_key AND g.organisation_key = f.organisation_key AND g.period_key = f.period_key
        AND g.account_key = f.account_key AND g.control_budget_key = f.control_budget_key
        AND sg.sub_segment_code = N'X903A003'
        AND SIGN(g.amount_delta) = -SIGN(f.amount_delta)
        AND ABS(ABS(g.amount_delta) - ABS(f.amount_delta)) <= 0.01 * ABS(f.amount_delta))
UNION ALL
SELECT 'the number of flagged fact rows is not thirteen', CAST(COUNT(*) AS nvarchar(10))
FROM dw.fact_outturn WHERE dq_issue_id IS NOT NULL
HAVING COUNT(*) <> 13
UNION ALL
SELECT 'the flagged rows are not six on X903A002 and seven on X903A003', sg.sub_segment_code + N' ' + CAST(COUNT(*) AS nvarchar(10))
FROM dw.fact_outturn AS f
JOIN dw.dim_segment AS sg ON sg.segment_key = f.segment_key
WHERE f.dq_issue_id IS NOT NULL
GROUP BY sg.sub_segment_code
HAVING COUNT(*) <> CASE sg.sub_segment_code WHEN N'X903A002' THEN 6 WHEN N'X903A003' THEN 7 END;
