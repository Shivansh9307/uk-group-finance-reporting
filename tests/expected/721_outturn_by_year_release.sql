-- Independent of the model: deltas by the financial year of the period and the label of the release.
SELECT p.financial_year AS [Financial Year], r.label AS [Release Label],
       CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS outturn
FROM dw.fact_outturn AS f
JOIN dw.dim_period AS p ON p.period_key = f.period_key
JOIN dw.dim_release AS r ON r.release_key = f.release_key
GROUP BY p.financial_year, r.label
ORDER BY p.financial_year, r.label;
