-- Independent of the model: dw.dq_issue.
SELECT dq_issue_id AS issue_key, issue_rule, issue_type, release_from, release_to, sub_segment_code AS sub_segment,
       CAST(amount_before AS decimal(38, 4)) AS amount_before, CAST(amount_after AS decimal(38, 4)) AS amount_after,
       CAST(rows_affected AS bigint) AS rows_affected
FROM dw.dq_issue
ORDER BY dq_issue_id;
