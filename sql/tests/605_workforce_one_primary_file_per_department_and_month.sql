-- test: each department series and month has exactly one primary copy among its loaded files, and only loaded files are primary
-- marker: localdata
-- requires: raw.workforce_file
SELECT TOP (20) dept, report_month, SUM(CAST(is_primary AS int)) AS primaries
FROM raw.workforce_file
WHERE load_status = 'loaded'
GROUP BY dept, report_month
HAVING SUM(CAST(is_primary AS int)) <> 1
UNION ALL
SELECT TOP (20) dept, report_month, 1
FROM raw.workforce_file
WHERE load_status = 'skipped' AND is_primary = 1;
