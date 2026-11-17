-- test: dim_period has 13 rows for each of the 11 financial years from 2018-19 to 2028-29; period 0 appears in the fact only for 2018-19 and does appear there
SELECT financial_year AS what, COUNT(*) AS n FROM dw.dim_period GROUP BY financial_year HAVING COUNT(*) <> 13
UNION ALL
SELECT 'years in dim_period', COUNT(DISTINCT financial_year) FROM dw.dim_period HAVING COUNT(DISTINCT financial_year) <> 11
UNION ALL
SELECT 'first or last year wrong', 1 FROM (VALUES (1)) AS one (x) WHERE (SELECT MIN(financial_year) FROM dw.dim_period) <> '2018-19' OR (SELECT MAX(financial_year) FROM dw.dim_period) <> '2028-29'
UNION ALL
SELECT 'period 0 in the fact outside 2018-19: ' + p.financial_year, COUNT(*)
FROM dw.fact_outturn AS f JOIN dw.dim_period AS p ON p.period_key = f.period_key
WHERE p.period = 0 AND p.financial_year <> '2018-19'
GROUP BY p.financial_year
UNION ALL
SELECT 'no period 0 rows in the fact for 2018-19', 1
FROM (VALUES (1)) AS one (x)
WHERE NOT EXISTS (SELECT 1 FROM dw.fact_outturn AS f JOIN dw.dim_period AS p ON p.period_key = f.period_key WHERE p.period = 0 AND p.financial_year = '2018-19')
UNION ALL
SELECT 'period 0 member has a month start date or a quarter: ' + CAST(period_key AS varchar(10)), 1
FROM dw.dim_period WHERE (CASE WHEN period = 0 THEN 1 ELSE 0 END) <> is_period0 OR (period = 0 AND (month_start_date IS NOT NULL OR fiscal_quarter IS NOT NULL))
UNION ALL
SELECT 'month start date or quarter wrong: ' + CAST(period_key AS varchar(10)), 1
FROM dw.dim_period
WHERE period BETWEEN 1 AND 12
  AND (month_start_date <> DATEFROMPARTS(fiscal_year_start + CASE WHEN period >= 10 THEN 1 ELSE 0 END, CASE WHEN period <= 9 THEN period + 3 ELSE period - 9 END, 1)
       OR fiscal_quarter <> (period + 2) / 3
       OR period_key <> fiscal_year_start * 100 + period);
