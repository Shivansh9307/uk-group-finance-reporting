-- Independent of the model: the fact summed by the name of the organisation version it was reported under, 2025-26.
SELECT TOP (10) o.organisation_name AS organisation, CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS outturn
FROM dw.fact_outturn AS f
JOIN dw.dim_period AS p ON p.period_key = f.period_key
JOIN dw.dim_organisation AS o ON o.organisation_key = f.organisation_key
WHERE p.financial_year = '2025-26'
GROUP BY o.organisation_name
ORDER BY SUM(f.amount_delta) DESC;
