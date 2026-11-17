-- test: rule a flags the NHS Pension Scheme lines (sub-segment X903A002) in the release pairs 2023-09 to 2023-12 and 2025-12 to 2026-03 and nothing else; the fact rows carrying a dq_issue_id are exactly the rows of those lines in those two releases of each pair
SELECT 'rule a flagged something other than the NHS Pension Scheme line' AS problem, i.dq_issue_id, i.release_from, i.sub_segment_code
FROM dw.dq_issue AS i
WHERE i.issue_rule = 'a'
  AND NOT (i.organisation_code = 'NHP903' AND i.sub_segment_code = 'X903A002' AND i.economic_category_code = 'NA'
           AND i.control_budget_detail_code = 'NON-BUDGET')
UNION ALL
SELECT 'release pair not flagged', NULL, p.release_from, 'X903A002'
FROM (VALUES ('2023-09', '2023-12'), ('2025-12', '2026-03')) AS p (release_from, release_to)
WHERE NOT EXISTS (SELECT 1 FROM dw.dq_issue AS i WHERE i.issue_rule = 'a' AND i.release_from = p.release_from AND i.release_to = p.release_to)
UNION ALL
SELECT 'rule a flagged a release pair that is not one of the two', i.dq_issue_id, i.release_from, i.sub_segment_code
FROM dw.dq_issue AS i
WHERE i.issue_rule = 'a' AND NOT (i.release_from = '2023-09' AND i.release_to = '2023-12' OR i.release_from = '2025-12' AND i.release_to = '2026-03')
UNION ALL
SELECT 'fact row carries an id but is not a delta row of a flagged line in a flagged release', f.dq_issue_id, CAST(f.release_key AS varchar(10)), NULL
FROM dw.fact_outturn AS f
JOIN dw.dq_issue AS i ON i.dq_issue_id = f.dq_issue_id
JOIN dw.dim_release AS r ON r.release_key = f.release_key
WHERE i.flags_fact_rows = 0 OR r.label NOT IN (i.release_from, i.release_to)
   OR f.organisation_key <> i.organisation_key OR f.segment_key <> i.segment_key OR f.account_key <> i.account_key
   OR f.control_budget_key <> i.control_budget_key OR f.period_key <> i.period_key
UNION ALL
SELECT 'fact row of a flagged line and release has no id', NULL, CAST(f.release_key AS varchar(10)), NULL
FROM dw.fact_outturn AS f
JOIN dw.dim_release AS r ON r.release_key = f.release_key
JOIN dw.dq_issue AS i
  ON i.flags_fact_rows = 1 AND r.label IN (i.release_from, i.release_to) AND f.organisation_key = i.organisation_key
 AND f.segment_key = i.segment_key AND f.account_key = i.account_key AND f.control_budget_key = i.control_budget_key
 AND f.period_key = i.period_key
WHERE f.dq_issue_id IS NULL
UNION ALL
SELECT 'only rule a may flag fact rows', i.dq_issue_id, i.release_from, NULL
FROM dw.dq_issue AS i
WHERE i.flags_fact_rows = 1 AND i.issue_rule <> 'a';
