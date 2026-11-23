-- test: rule a flags the NHS Pension Scheme lines (sub-segment X903A002 as a unit error, X903A003 as its offsetting line, three findings each) in the release pairs 2023-09 to 2023-12 and 2025-12 to 2026-03 and nothing else; the fact rows carrying a dq_issue_id are exactly, for each finding, the delta rows of the line-month from the one that set the amount (the delta row of largest absolute size at or before the first release of the pair) to the one that corrected it
SELECT 'rule a flagged something other than the NHS Pension Scheme lines' AS problem, i.dq_issue_id, i.release_from, i.sub_segment_code
FROM dw.dq_issue AS i
WHERE i.issue_rule = 'a'
  AND NOT (i.organisation_code = 'NHP903' AND i.economic_category_code = 'NA' AND i.control_budget_detail_code = 'NON-BUDGET'
           AND ((i.sub_segment_code = 'X903A002' AND i.issue_type = 'unit error')
             OR (i.sub_segment_code = 'X903A003' AND i.issue_type = 'unit error (offsetting line)')))
UNION ALL
SELECT 'release pair not flagged for the line', NULL, p.release_from, t.sub_segment_code
FROM (VALUES ('2023-09', '2023-12'), ('2025-12', '2026-03')) AS p (release_from, release_to)
CROSS JOIN (VALUES ('X903A002', 'unit error'), ('X903A003', 'unit error (offsetting line)')) AS t (sub_segment_code, issue_type)
WHERE NOT EXISTS (SELECT 1 FROM dw.dq_issue AS i WHERE i.issue_rule = 'a' AND i.release_from = p.release_from AND i.release_to = p.release_to
                  AND i.sub_segment_code = t.sub_segment_code AND i.issue_type = t.issue_type)
UNION ALL
SELECT 'rule a does not have three findings for the line', NULL, NULL, t.sub_segment_code
FROM (VALUES ('X903A002'), ('X903A003')) AS t (sub_segment_code)
WHERE (SELECT COUNT(*) FROM dw.dq_issue AS i WHERE i.issue_rule = 'a' AND i.sub_segment_code = t.sub_segment_code) <> 3
UNION ALL
SELECT 'rule a flagged a release pair that is not one of the two', i.dq_issue_id, i.release_from, i.sub_segment_code
FROM dw.dq_issue AS i
WHERE i.issue_rule = 'a' AND NOT (i.release_from = '2023-09' AND i.release_to = '2023-12' OR i.release_from = '2025-12' AND i.release_to = '2026-03')
UNION ALL
SELECT 'fact row carries an id but is outside the rows from the one that set the amount to the one that corrected it', f.dq_issue_id, CAST(f.release_key AS varchar(10)), NULL
FROM dw.fact_outturn AS f
JOIN dw.dq_issue AS i ON i.dq_issue_id = f.dq_issue_id
JOIN dw.dim_release AS rf ON rf.label = i.release_from
JOIN dw.dim_release AS rt ON rt.label = i.release_to
WHERE i.flags_fact_rows = 0
   OR f.organisation_key <> i.organisation_key OR f.segment_key <> i.segment_key OR f.account_key <> i.account_key
   OR f.control_budget_key <> i.control_budget_key OR f.period_key <> i.period_key
   OR f.release_key > rt.release_key
   OR f.release_key < (SELECT TOP (1) g.release_key FROM dw.fact_outturn AS g
                       WHERE g.organisation_key = i.organisation_key AND g.segment_key = i.segment_key AND g.account_key = i.account_key
                         AND g.control_budget_key = i.control_budget_key AND g.period_key = i.period_key AND g.release_key <= rf.release_key
                       ORDER BY ABS(g.amount_delta) DESC, g.release_key)
UNION ALL
SELECT 'fact row from the one that set the amount to the one that corrected it has no id', i.dq_issue_id, CAST(g.release_key AS varchar(10)), NULL
FROM dw.dq_issue AS i
JOIN dw.dim_release AS rf ON rf.label = i.release_from
JOIN dw.dim_release AS rt ON rt.label = i.release_to
JOIN dw.fact_outturn AS g
  ON g.organisation_key = i.organisation_key AND g.segment_key = i.segment_key AND g.account_key = i.account_key
 AND g.control_budget_key = i.control_budget_key AND g.period_key = i.period_key
WHERE i.flags_fact_rows = 1 AND g.dq_issue_id IS NULL
  AND g.release_key <= rt.release_key
  AND g.release_key >= (SELECT TOP (1) h.release_key FROM dw.fact_outturn AS h
                        WHERE h.organisation_key = i.organisation_key AND h.segment_key = i.segment_key AND h.account_key = i.account_key
                          AND h.control_budget_key = i.control_budget_key AND h.period_key = i.period_key AND h.release_key <= rf.release_key
                        ORDER BY ABS(h.amount_delta) DESC, h.release_key)
UNION ALL
SELECT 'only rule a may flag fact rows', i.dq_issue_id, i.release_from, NULL
FROM dw.dq_issue AS i
WHERE i.flags_fact_rows = 1 AND i.issue_rule <> 'a';
