-- Independent of the model: the fact by period of 2025-26, and the sum of all its periods as the year to date at 12.
SELECT 'p' + RIGHT('0' + CAST(p.period AS varchar(2)), 2) AS item, CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS value
FROM dw.fact_outturn AS f JOIN dw.dim_period AS p ON p.period_key = f.period_key
WHERE p.financial_year = '2025-26'
GROUP BY p.period
UNION ALL
SELECT 'ytd_p12', CAST(SUM(f.amount_delta) AS decimal(38, 4))
FROM dw.fact_outturn AS f JOIN dw.dim_period AS p ON p.period_key = f.period_key
WHERE p.financial_year = '2025-26';
