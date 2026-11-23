-- Independent of the model: the fact by release, all deltas, those with a revision number above 0, and their absolute
-- values, with and without the rows that carry a data-quality finding. A release with no restating row has no restatement.
SELECT r.label AS release, CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS revision,
       CAST(SUM(CASE WHEN f.revision_no > 0 THEN f.amount_delta END) AS decimal(38, 4)) AS restatement,
       CAST(SUM(CASE WHEN f.revision_no > 0 THEN ABS(f.amount_delta) END) AS decimal(38, 4)) AS gross_restatement,
       CAST(SUM(CASE WHEN f.revision_no > 0 AND f.dq_issue_id IS NULL THEN ABS(f.amount_delta) END) AS decimal(38, 4)) AS gross_restatement_excl
FROM dw.fact_outturn AS f
JOIN dw.dim_release AS r ON r.release_key = f.release_key
GROUP BY r.label
ORDER BY r.label;
