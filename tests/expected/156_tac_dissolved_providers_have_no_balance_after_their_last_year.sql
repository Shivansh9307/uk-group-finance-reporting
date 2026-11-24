-- requires: dw.tac_fact
-- Independent of the model: cash and cash equivalents (BAL1240) of nine predecessors from dw.tac_fact, by year. The
-- closing cash is the current-year column of that year's file, 0 where the provider has no file that year; the
-- carried-forward cash is the latest current-year column up to the year, 0 before the first.
WITH cash AS (
    SELECT p.provider_code, f.release, f.value
    FROM dw.tac_fact AS f
    JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key AND l.sub_code = 'BAL1240'
    JOIN dw.tac_provider AS p ON p.provider_key = f.provider_key
    WHERE f.period_column = 'CY'
),
pr AS (SELECT provider_code FROM dw.tac_provider WHERE provider_code IN ('RBA', 'RD3', 'RDZ', 'RT3', 'RW6', 'RBZ', 'RA4', 'RVY', 'R1J')),
yr AS (SELECT DISTINCT release FROM dw.tac_fact)
SELECT pr.provider_code AS [Provider Code], yr.release AS [Financial Year],
       CAST(ISNULL((SELECT SUM(c.value) FROM cash AS c WHERE c.provider_code = pr.provider_code AND c.release = yr.release), 0) AS decimal(38, 4)) AS closing_cash,
       CAST(ISNULL((SELECT TOP (1) c.value FROM cash AS c WHERE c.provider_code = pr.provider_code AND c.release <= yr.release ORDER BY c.release DESC), 0) AS decimal(38, 4)) AS carried_forward_cash
FROM pr CROSS JOIN yr
ORDER BY pr.provider_code, yr.release;
