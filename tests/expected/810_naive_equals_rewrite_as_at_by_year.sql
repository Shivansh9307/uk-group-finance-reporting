-- Independent of the model: the sum of the deltas of each financial year up to and including each release (a running
-- sum over the releases in publication order). The plain and the rewritten measure must both equal it, so the
-- difference is 0.
SELECT r.label AS release, p.financial_year AS financial_year,
       CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS as_at_naive,
       CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS as_at_rewrite,
       CAST(0 AS decimal(38, 4)) AS difference
FROM dw.dim_release AS r
JOIN dw.fact_outturn AS f ON f.release_key <= r.release_key
JOIN dw.dim_period AS p ON p.period_key = f.period_key
GROUP BY r.label, p.financial_year
ORDER BY r.label, p.financial_year;
