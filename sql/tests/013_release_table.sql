-- test: stg.release has one row per release, sequence 1..31 in publication order, one version label, a financial year and a highest period that match the rule
-- Returns each broken expectation as a row.

WITH expected AS (
    SELECT r.release, r.release_seq, r.financial_year, r.highest_period, r.first_published,
           CAST(LEFT(r.release, 4) AS int) - CASE WHEN RIGHT(r.release, 2) IN ('03', '06') THEN 1 ELSE 0 END AS fy_start,
           CASE RIGHT(r.release, 2) WHEN '03' THEN 9 WHEN '06' THEN 12 WHEN '09' THEN 3 WHEN '12' THEN 6 END AS max_period
    FROM stg.release AS r
)
SELECT release, 'financial year or highest period differs from the release rule' AS problem
FROM expected
WHERE financial_year <> CAST(fy_start AS varchar(4)) + '-' + RIGHT(CAST(fy_start + 1 AS varchar(4)), 2)
   OR highest_period <> max_period
UNION ALL
SELECT release, 'sequence is not the publication order'
FROM stg.release AS r
WHERE r.release_seq <> (SELECT COUNT(*) FROM stg.release AS x
                        WHERE x.first_published < r.first_published
                           OR (x.first_published = r.first_published AND x.release <= r.release))
UNION ALL
SELECT release, 'first_published is before the first day of the release month'
FROM expected
WHERE first_published < DATEFROMPARTS(CAST(LEFT(release, 4) AS int), CAST(RIGHT(release, 2) AS int), 1)
UNION ALL
SELECT 'all', 'release count or sequence is not 1..31'
WHERE (SELECT COUNT(*) FROM stg.release) <> 31
   OR (SELECT MIN(release_seq) FROM stg.release) <> 1
   OR (SELECT MAX(release_seq) FROM stg.release) <> 31
UNION ALL
SELECT CAST(f.release AS varchar(7)), 'release holds more than one version label'
FROM raw.oscar_inyear AS r
JOIN raw.oscar_inyear_file AS f ON f.file_id = r.file_id
GROUP BY f.release
HAVING COUNT(DISTINCT r.version) <> 1;
