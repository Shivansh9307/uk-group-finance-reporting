-- Independent of the model: the deltas of 2025-26 in releases up to and including 2026-03, all of them and those with
-- revision number 0.
WITH t AS (
    SELECT SUM(f.amount_delta) AS as_at, SUM(CASE WHEN f.revision_no = 0 THEN f.amount_delta ELSE 0 END) AS first_reported
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    JOIN dw.dim_release AS r ON r.release_key = f.release_key
    WHERE p.financial_year = '2025-26' AND r.label <= '2026-03'
)
SELECT 'as_at' AS item, CAST(as_at AS decimal(38, 4)) AS value FROM t
UNION ALL SELECT 'first_reported', CAST(first_reported AS decimal(38, 4)) FROM t
UNION ALL SELECT 'revision', CAST(as_at - first_reported AS decimal(38, 4)) FROM t;
