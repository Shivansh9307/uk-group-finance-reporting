-- Independent of the model: the in-year plan-basis table at the last release of each financial year, summed over
-- the periods, for the (year, group, measure) cells that have a plan row and a basis other than zero (the table keeps
-- no zero rows; the model returns 0 for cells whose lines net to zero, and the DAX test leaves those out too).
SELECT b.financial_year AS [Financial Year], g.sr_group_name AS [Spending Review Group], b.measure AS [Plan Measure],
       CAST(SUM(b.amount) AS decimal(38, 4)) AS basis
FROM dw.outturn_plan_basis_inyear AS b
JOIN dw.dim_sr_group AS g ON g.sr_group_key = b.sr_group_key
WHERE b.release_key = (SELECT MAX(r.release_key) FROM dw.dim_release AS r WHERE r.financial_year = b.financial_year)
  AND EXISTS (SELECT 1 FROM dw.fact_plan AS p
              WHERE p.financial_year = b.financial_year AND p.sr_group_key = b.sr_group_key AND p.measure = b.measure)
GROUP BY b.financial_year, g.sr_group_name, b.measure
HAVING SUM(b.amount) <> 0
ORDER BY b.financial_year, g.sr_group_name, b.measure;
