-- test: pins a limit of the data-quality finding. Each of the six fact rows flagged for the NHS Pension Scheme unit error (line X903A002) has, in the same release, organisation, period, economic category and control budget, an unflagged row on line X903A003 of the opposite sign within one per cent of its size: the scheme's offsetting line carries the error too and is not flagged, because its change from one release to the next is not a factor of 900 to 1,100. The restatement measures that leave out flagged rows therefore leave the mirror in. If rule a ever flags the mirror, this test fails and the documentation of the restatement measures changes with it.
SELECT 'a flagged row has no unflagged mirror line' AS problem, CAST(f.release_key AS nvarchar(10)) + N' ' + CAST(f.period_key AS nvarchar(10)) AS detail
FROM dw.fact_outturn AS f
WHERE f.dq_issue_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM dw.fact_outturn AS g
      JOIN dw.dim_segment AS sg ON sg.segment_key = g.segment_key
      WHERE g.release_key = f.release_key AND g.organisation_key = f.organisation_key AND g.period_key = f.period_key
        AND g.account_key = f.account_key AND g.control_budget_key = f.control_budget_key
        AND sg.sub_segment_code = N'X903A003' AND g.dq_issue_id IS NULL
        AND SIGN(g.amount_delta) = -SIGN(f.amount_delta)
        AND ABS(ABS(g.amount_delta) - ABS(f.amount_delta)) <= 0.01 * ABS(f.amount_delta))
UNION ALL
SELECT 'the number of flagged rows is not six', CAST(COUNT(*) AS nvarchar(10))
FROM dw.fact_outturn WHERE dq_issue_id IS NOT NULL
HAVING COUNT(*) <> 6;
