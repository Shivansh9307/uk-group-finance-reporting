-- requires: dw.fact_allocation, dw.dim_department
-- Independent of the model views: the allocation fact by year and department number. The weight is worked out again as the
-- department's average full-time equivalent over the sum of the year's participants (the model sums the stored weight). The ratio is worked in
-- float in this query only, because decimal division here would keep six decimals and hide an error in the model's ten.
SELECT f.financial_year, d.department_number,
       CAST(CAST(f.avg_fte AS float) / SUM(CAST(f.avg_fte AS float)) OVER (PARTITION BY f.rule_id, f.financial_year) AS decimal(38, 10)) AS [weight],
       CAST(f.avg_fte AS decimal(38, 4)) AS fte,
       CAST(f.allocated_amount AS decimal(38, 4)) AS allocated,
       CAST(f.paybill_annualised AS decimal(38, 4)) AS paybill,
       CAST(f.rounding_adjustment AS decimal(38, 4)) AS rounding
FROM dw.fact_allocation AS f
JOIN dw.dim_department AS d ON d.department_key = f.department_key
ORDER BY f.financial_year, d.department_number;
