-- test: for every Estimates and PESA year and measure in dw.fact_plan, the sum of the fact rows (reserves, the Single Intelligence Account and other non-department lines included) equals the sheet's own published total, converted to GBP thousands, within the rounding of the published figures
WITH fact AS (
    SELECT s.family, s.edition, f.financial_year, f.measure AS fact_measure,
           CASE f.measure WHEN 'RAME' THEN 'RESOURCE_DEPT_AME' WHEN 'CAME' THEN 'CAPITAL_DEPT_AME' ELSE f.measure END AS sheet_measure,
           SUM(f.amount) AS amount
    FROM dw.fact_plan AS f
    JOIN dw.dim_plan_source AS s ON s.plan_source_key = f.plan_source_key
    WHERE s.family IN ('estimates', 'pesa')
    GROUP BY s.family, s.edition, f.financial_year, f.measure
),
ctrl AS (
    SELECT family, edition, year_label, measure, COUNT(*) AS n, MAX(published_total) AS published_total,
           MAX(tolerance) AS tolerance, MAX(unit) AS unit
    FROM audit.plan_sheet_control
    WHERE status_label = 'plans'
    GROUP BY family, edition, year_label, measure
)
SELECT f.family, f.edition, f.financial_year, f.fact_measure, f.amount,
       c.published_total, 'no single control row for this year and measure' AS problem
FROM fact AS f
LEFT JOIN ctrl AS c ON c.family = f.family AND c.edition = f.edition AND c.year_label = f.financial_year AND c.measure = f.sheet_measure
WHERE c.n IS NULL OR c.n <> 1
UNION ALL
SELECT f.family, f.edition, f.financial_year, f.fact_measure, f.amount,
       c.published_total * m.mult, 'fact total differs from the published total'
FROM fact AS f
JOIN ctrl AS c ON c.family = f.family AND c.edition = f.edition AND c.year_label = f.financial_year AND c.measure = f.sheet_measure AND c.n = 1
CROSS APPLY (SELECT CASE WHEN LOWER(c.unit) LIKE '%billion%' THEN 1000000 WHEN LOWER(c.unit) LIKE '%million%' THEN 1000 END AS mult) AS m
WHERE c.published_total IS NULL OR m.mult IS NULL
   OR ABS(f.amount - c.published_total * m.mult) > c.tolerance * m.mult + 0.001;
