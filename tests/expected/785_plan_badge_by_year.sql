-- Independent of the model: the plan sources and grains of the rows of dw.fact_plan that are not part of another
-- measure, per financial year, in the order of the source's edition label.
SELECT x.financial_year,
       STRING_AGG(CAST(x.label AS nvarchar(max)), N'; ') WITHIN GROUP (ORDER BY x.edition_label) AS badge
FROM (
    SELECT DISTINCT f.financial_year, s.edition_label, s.edition_label + N' at ' + g.grain_name AS label
    FROM dw.fact_plan AS f
    JOIN dw.dim_plan_source AS s ON s.plan_source_key = f.plan_source_key
    JOIN dw.dim_plan_grain AS g ON g.grain_code = f.grain_code
    WHERE f.is_part_of_other_measure = 0
) AS x
GROUP BY x.financial_year
ORDER BY x.financial_year;
