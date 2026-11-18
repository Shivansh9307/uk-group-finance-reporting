-- Independent of the model: what leaving out the six flagged fact rows leaves, read from dw.dq_issue and the fact.
-- As at: the flagged deltas of the release's financial year up to and including the release are what is taken off.
-- Gross: the absolute deltas of the release, all of them and those with a revision number above 0, with and without the
-- flagged rows; and, for the last column, without any row of the two NHS Pension Scheme lines X903A002 and X903A003.
-- A release with no row with a revision number above 0 has no gross restatement (missing, not zero).
WITH flagged AS (
    SELECT f.release_key, f.amount_delta
    FROM dw.fact_outturn AS f
    JOIN dw.dq_issue AS i ON i.dq_issue_id = f.dq_issue_id
    WHERE i.flags_fact_rows = 1
), rows_ AS (
    SELECT f.release_key, f.revision_no, ABS(f.amount_delta) AS a,
           CASE WHEN f.dq_issue_id IS NULL THEN 0 ELSE 1 END AS is_flagged,
           CASE WHEN sg.sub_segment_code IN (N'X903A002', N'X903A003') THEN 1 ELSE 0 END AS in_pair
    FROM dw.fact_outturn AS f
    JOIN dw.dim_segment AS sg ON sg.segment_key = f.segment_key
)
SELECT r.label AS release,
       CAST(ISNULL((SELECT SUM(x.amount_delta) FROM flagged AS x JOIN dw.dim_release AS xr ON xr.release_key = x.release_key
                    WHERE xr.financial_year = r.financial_year AND x.release_key <= r.release_key), 0) AS decimal(38, 4)) AS removed_as_at,
       CAST((SELECT SUM(a) FROM rows_ WHERE release_key = r.release_key) AS decimal(38, 4)) AS gross,
       CAST((SELECT SUM(a) FROM rows_ WHERE release_key = r.release_key AND is_flagged = 0) AS decimal(38, 4)) AS gross_excl,
       CAST((SELECT SUM(a) FROM rows_ WHERE release_key = r.release_key AND revision_no > 0) AS decimal(38, 4)) AS gross_restatement,
       CAST((SELECT SUM(a) FROM rows_ WHERE release_key = r.release_key AND revision_no > 0 AND is_flagged = 0) AS decimal(38, 4)) AS gross_restatement_excl,
       CAST((SELECT SUM(a) FROM rows_ WHERE release_key = r.release_key AND revision_no > 0 AND in_pair = 0) AS decimal(38, 4)) AS gross_restatement_without_pair
FROM dw.dim_release AS r
ORDER BY r.label;
