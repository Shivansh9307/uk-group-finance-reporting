-- requires: dw.tac_fact
-- Independent of the model: cash and cash equivalents (BAL1240), current-year column, from dw.tac_fact. The closing
-- cash is the sum over the providers with a file in the year; the carried-forward cash adds, for every provider, its
-- latest balance up to the year (so a provider that has gone stays in); the overstatement is the difference.
WITH cash AS (
    SELECT f.provider_key, f.release, f.value
    FROM dw.tac_fact AS f JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key AND l.sub_code = 'BAL1240'
    WHERE f.period_column = 'CY'
),
yr AS (SELECT DISTINCT release FROM cash),
carried AS (
    SELECT y.release, p.provider_key,
           (SELECT TOP (1) c.value FROM cash AS c WHERE c.provider_key = p.provider_key AND c.release <= y.release ORDER BY c.release DESC) AS last_value
    FROM yr AS y CROSS JOIN (SELECT DISTINCT provider_key FROM cash) AS p
)
SELECT y.release AS [Financial Year],
       CAST((SELECT SUM(value) FROM cash AS c WHERE c.release = y.release) AS decimal(38, 4)) AS closing_cash,
       (SELECT COUNT_BIG(DISTINCT provider_key) FROM cash AS c WHERE c.release = y.release) AS providers_reporting,
       CAST((SELECT SUM(last_value) FROM carried AS k WHERE k.release = y.release) AS decimal(38, 4)) AS carried_forward_cash,
       CAST((SELECT SUM(last_value) FROM carried AS k WHERE k.release = y.release) - (SELECT SUM(value) FROM cash AS c WHERE c.release = y.release) AS decimal(38, 4)) AS overstatement
FROM yr AS y
ORDER BY y.release;
