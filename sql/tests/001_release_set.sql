-- test: every quarterly release from 2019-03 to 2026-09 (31 of them) has exactly one loaded primary file
-- Returns the releases that are missing, unexpected, or have more or fewer than one primary file.

WITH n AS (
    SELECT TOP (31) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i FROM sys.all_objects
), expected AS (
    SELECT CAST(CONVERT(char(7), DATEADD(MONTH, 3 * n.i, CAST('2019-03-01' AS date)), 126) AS varchar(7)) AS release
    FROM n
), actual AS (
    SELECT release, COUNT(*) AS primaries
    FROM raw.oscar_inyear_file
    WHERE primary_for_release = 'Y'
    GROUP BY release
)
SELECT COALESCE(e.release, a.release) AS release, a.primaries
FROM expected AS e
FULL JOIN actual AS a ON a.release = e.release
WHERE e.release IS NULL OR a.release IS NULL OR a.primaries <> 1;
