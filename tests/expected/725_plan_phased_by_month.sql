-- Independent of the model: the phased fact by the financial year and the period of its period key. Plan is blank
-- in every month cell by the rule of the guard, so the expected flag is 1.
SELECT d.financial_year AS [Financial Year], d.period AS [Period Number],
       CAST(SUM(f.amount) AS decimal(38, 4)) AS phased, CAST(1 AS int) AS plan_is_blank
FROM dw.fact_plan_phased AS f
JOIN dw.dim_period AS d ON d.period_key = f.period_key
WHERE f.is_part_of_other_measure = 0
GROUP BY d.financial_year, d.period
ORDER BY d.financial_year, d.period;
