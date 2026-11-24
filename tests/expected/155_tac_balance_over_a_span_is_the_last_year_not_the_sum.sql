-- requires: dw.tac_fact
-- Independent of the model: cash and cash equivalents (BAL1240) from dw.tac_fact. Closing = the current-year column of the
-- last year of the span; opening = the prior-year column of the first year; the sum of the years' closing balances;
-- the providers with statements in the last year.
WITH cash AS (
    SELECT f.release, f.period_column, f.provider_key, f.value
    FROM dw.tac_fact AS f JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key AND l.sub_code = 'BAL1240'
),
span AS (
    SELECT * FROM (VALUES
        ('2019-20 to 2021-22', '2019-20', '2021-22'),
        ('2022-23 to 2024-25', '2022-23', '2024-25'),
        ('2019-20 and 2024-25 only', '2019-20', '2024-25'),
        ('all years, no year filter', '2019-20', '2024-25')
    ) AS s(span, first_year, last_year)
),
members AS (
    SELECT 'all years, no year filter' AS span, release FROM (SELECT DISTINCT release FROM cash) AS y
    UNION ALL SELECT '2019-20 to 2021-22', release FROM (SELECT DISTINCT release FROM cash) AS y WHERE release IN ('2019-20', '2020-21', '2021-22')
    UNION ALL SELECT '2022-23 to 2024-25', release FROM (SELECT DISTINCT release FROM cash) AS y WHERE release IN ('2022-23', '2023-24', '2024-25')
    UNION ALL SELECT '2019-20 and 2024-25 only', release FROM (SELECT DISTINCT release FROM cash) AS y WHERE release IN ('2019-20', '2024-25')
)
SELECT s.span AS span,
       CAST((SELECT SUM(c.value) FROM cash AS c WHERE c.period_column = 'CY' AND c.release = s.last_year) AS decimal(38, 4)) AS closing_balance,
       CAST((SELECT SUM(c.value) FROM cash AS c WHERE c.period_column = 'PY' AND c.release = s.first_year) AS decimal(38, 4)) AS opening_balance,
       CAST((SELECT SUM(c.value) FROM cash AS c JOIN members AS m ON m.release = c.release AND m.span = s.span WHERE c.period_column = 'CY') AS decimal(38, 4)) AS sum_of_years_closing,
       (SELECT COUNT_BIG(DISTINCT c.provider_key) FROM cash AS c WHERE c.period_column = 'CY' AND c.release = s.last_year) AS providers_reporting
FROM span AS s
ORDER BY s.span;
