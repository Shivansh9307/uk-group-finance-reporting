-- test: dw.plan_coverage and audit.plan_coverage describe dw.fact_plan exactly: same rows, source lines and totals per plan source, year, measure and grain
WITH f AS (
    SELECT s.plan_source_code, p.financial_year, p.measure, p.grain_code, COUNT(*) AS row_count,
           SUM(p.source_line_count) AS source_line_count, SUM(p.amount) AS amount_total
    FROM dw.fact_plan AS p JOIN dw.dim_plan_source AS s ON s.plan_source_key = p.plan_source_key
    GROUP BY s.plan_source_code, p.financial_year, p.measure, p.grain_code
),
c AS (
    SELECT s.plan_source_code, c.financial_year, c.measure, c.grain_code, c.row_count, c.source_line_count, c.amount_total
    FROM dw.plan_coverage AS c JOIN dw.dim_plan_source AS s ON s.plan_source_key = c.plan_source_key
)
SELECT COALESCE(f.plan_source_code, c.plan_source_code) AS plan_source_code, COALESCE(f.financial_year, c.financial_year) AS financial_year,
       COALESCE(f.measure, c.measure) AS measure, 'dw.plan_coverage differs from dw.fact_plan' AS problem
FROM f FULL OUTER JOIN c
  ON c.plan_source_code = f.plan_source_code AND c.financial_year = f.financial_year AND c.measure = f.measure AND c.grain_code = f.grain_code
WHERE f.plan_source_code IS NULL OR c.plan_source_code IS NULL OR f.row_count <> c.row_count
   OR f.source_line_count <> c.source_line_count OR f.amount_total <> c.amount_total
UNION ALL
SELECT a.plan_source_code, a.financial_year, a.measure, 'audit.plan_coverage differs from dw.fact_plan'
FROM audit.plan_coverage AS a
LEFT JOIN f ON f.plan_source_code = a.plan_source_code AND f.financial_year = a.financial_year AND f.measure = a.measure AND f.grain_code = a.grain_code
WHERE f.plan_source_code IS NULL OR f.row_count <> a.row_count OR f.amount_total <> a.amount_total
UNION ALL
SELECT 'all', NULL, NULL, 'row counts differ between dw.plan_coverage and audit.plan_coverage'
WHERE (SELECT COUNT(*) FROM dw.plan_coverage) <> (SELECT COUNT(*) FROM audit.plan_coverage)
UNION ALL
SELECT s.plan_source_code, NULL, NULL, 'dim_plan_source.fact_plan_rows differs from the fact'
FROM dw.dim_plan_source AS s
WHERE s.fact_plan_rows <> (SELECT COUNT(*) FROM dw.fact_plan AS p WHERE p.plan_source_key = s.plan_source_key);
