-- Independent of the model: the plan fact itself, counted and summed by source, year, measure and grain.
SELECT s.plan_source_code, f.financial_year, f.measure, f.grain_code AS grain, COUNT(*) AS fact_rows,
       CAST(SUM(f.source_line_count) AS bigint) AS source_lines, CAST(SUM(f.amount) AS decimal(38, 4)) AS amount_total
FROM dw.fact_plan AS f
JOIN dw.dim_plan_source AS s ON s.plan_source_key = f.plan_source_key
GROUP BY s.plan_source_code, f.financial_year, f.measure, f.grain_code
ORDER BY s.plan_source_code, f.financial_year, f.measure, f.grain_code;
