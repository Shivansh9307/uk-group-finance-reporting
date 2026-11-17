-- test: every delta row of a release is in the release's own financial year
SELECT f.release_key, r.financial_year AS release_year, p.financial_year AS period_year, COUNT(*) AS fact_rows
FROM dw.fact_outturn AS f
JOIN dw.dim_release AS r ON r.release_key = f.release_key
JOIN dw.dim_period AS p ON p.period_key = f.period_key
WHERE p.financial_year <> r.financial_year
GROUP BY f.release_key, r.financial_year, p.financial_year;
