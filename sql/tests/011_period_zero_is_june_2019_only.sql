-- test: the 71 "Period 0 - 18-19" rows exist in release 2019-06 and nowhere else, and stay in the staged table as period 0
-- They are kept as period 0 of FY2018-19 ("not allocated to a month"), included in year totals.
-- Zero-amount rows are dropped from the staged table, so the staged count may be lower than 71.

WITH raw_p0 AS (
    SELECT release, COUNT_BIG(*) AS n
    FROM raw.oscar_inyear
    WHERE [month] LIKE 'Period 0%'
    GROUP BY release
), stg_p0 AS (
    SELECT release, financial_year, COUNT_BIG(*) AS n
    FROM stg.inyear_snapshot
    WHERE period = 0
    GROUP BY release, financial_year
)
SELECT COALESCE(r.release, s.release) AS release, r.n AS raw_period0_rows, s.financial_year, s.n AS staged_period0_rows
FROM raw_p0 AS r
FULL JOIN stg_p0 AS s ON s.release = r.release
WHERE COALESCE(r.release, s.release) <> '2019-06'
   OR r.n IS NULL OR r.n <> 71
   OR s.n IS NULL OR s.n > r.n OR s.financial_year <> '2018-19'
UNION ALL
SELECT '2019-06', NULL, NULL, NULL
WHERE NOT EXISTS (SELECT 1 FROM raw_p0 WHERE release = '2019-06');
