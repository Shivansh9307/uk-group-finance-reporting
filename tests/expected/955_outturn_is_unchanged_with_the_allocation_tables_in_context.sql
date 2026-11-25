-- requires: dw.fact_outturn, dw.dim_period
-- Independent of the model views and of every allocation object: the sum of the revision deltas of the real outturn by financial year,
-- the same number in all three columns.
SELECT p.financial_year, CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS outturn,
       CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS with_allocation,
       CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS without_allocation
FROM dw.fact_outturn AS f
JOIN dw.dim_period AS p ON p.period_key = f.period_key
GROUP BY p.financial_year
HAVING SUM(f.amount_delta) <> 0
ORDER BY p.financial_year;
