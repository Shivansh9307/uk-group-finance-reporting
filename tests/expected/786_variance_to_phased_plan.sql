-- Independent of the model: the plan-basis table at the last release of the year, summed over the groups and periods 0
-- to p for the measures that have a plan row (not part of another measure) in the year, against the phased plan summed
-- over the same periods; the difference and the difference over the absolute phased plan, in parts per million.
WITH cells AS (
    SELECT v.fy AS financial_year, v.p AS period
    FROM (VALUES ('2024-25', 12), ('2025-26', 12), ('2026-27', 3), ('2026-27', 6)) AS v (fy, p)
), basis AS (
    SELECT c.financial_year, c.period, SUM(b.amount) AS amount
    FROM cells AS c
    JOIN dw.outturn_plan_basis_inyear AS b
      ON b.financial_year = c.financial_year AND b.period_no <= c.period
     AND b.release_key = (SELECT MAX(r.release_key) FROM dw.dim_release AS r WHERE r.financial_year = c.financial_year)
    WHERE b.measure IN (SELECT DISTINCT p.measure FROM dw.fact_plan AS p WHERE p.financial_year = c.financial_year AND p.is_part_of_other_measure = 0)
    GROUP BY c.financial_year, c.period
), phased AS (
    SELECT c.financial_year, c.period, SUM(f.amount) AS amount
    FROM cells AS c
    JOIN dw.fact_plan_phased AS f ON f.financial_year = c.financial_year AND f.period_no <= c.period
    WHERE f.is_part_of_other_measure = 0
    GROUP BY c.financial_year, c.period
)
SELECT c.financial_year, c.period, CAST(b.amount AS decimal(38, 4)) AS outturn_plan_basis, CAST(p.amount AS decimal(38, 4)) AS phased_plan,
       CAST(b.amount - p.amount AS decimal(38, 4)) AS variance,
       CAST((b.amount - p.amount) * 1000000 / ABS(p.amount) AS decimal(38, 4)) AS variance_ppm
FROM cells AS c
JOIN basis AS b ON b.financial_year = c.financial_year AND b.period = c.period
JOIN phased AS p ON p.financial_year = c.financial_year AND p.period = c.period
ORDER BY c.financial_year, c.period;
