-- Independent of the model: the year totals of dw.fact_outturn; the statement total and the sum of the detail lines must
-- both equal them, so the same number is expected in all three columns.
SELECT p.financial_year AS [Financial Year],
       CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS statement_total,
       CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS outturn,
       CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS detail_lines_as_reported
FROM dw.fact_outturn AS f
JOIN dw.dim_period AS p ON p.period_key = f.period_key
GROUP BY p.financial_year
ORDER BY p.financial_year;
