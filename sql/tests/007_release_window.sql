-- test: each release covers exactly its expected year to date, in its own financial year
-- Rule (checked independently of the load): a March release holds periods 1-9 and a June release
-- periods 1-12 of the financial year that began the year before; a September release holds periods
-- 1-3 and a December release periods 1-6 of the financial year that began that year. Period 0 is
-- allowed only in release 2019-06. Returns the releases (or months) that break the rule.

WITH window_rule AS (
    SELECT r.release,
           CAST(LEFT(r.release, 4) AS int) - CASE WHEN RIGHT(r.release, 2) IN ('03', '06') THEN 1 ELSE 0 END AS fy_start,
           CASE RIGHT(r.release, 2) WHEN '03' THEN 9 WHEN '06' THEN 12 WHEN '09' THEN 3 WHEN '12' THEN 6 END AS max_period
    FROM stg.release AS r
), expected AS (
    SELECT release,
           CAST(fy_start AS varchar(4)) + '-' + RIGHT(CAST(fy_start + 1 AS varchar(4)), 2) AS financial_year,
           max_period
    FROM window_rule
), found AS (
    SELECT release, financial_year, period, COUNT_BIG(*) AS n
    FROM stg.inyear_snapshot
    GROUP BY release, financial_year, period
)
-- 1. a row outside the expected financial year or period range
SELECT f.release, f.financial_year, f.period, 'outside the expected window' AS problem
FROM found AS f
JOIN expected AS e ON e.release = f.release
WHERE f.financial_year <> e.financial_year
   OR f.period > e.max_period
   OR (f.period = 0 AND f.release <> '2019-06')
UNION ALL
-- 2. a period of the window with no staged rows at all
SELECT e.release, e.financial_year, p.period, 'period missing'
FROM expected AS e
CROSS APPLY (SELECT TOP (e.max_period) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS period FROM sys.all_objects) AS p
WHERE NOT EXISTS (SELECT 1 FROM found AS f WHERE f.release = e.release AND f.period = p.period);
