-- test: fiscal_quarter is derived from the month: (period + 2) / 3 for periods 1-12, NULL for period 0
-- The Quarter column of the source is never used (every row of September 2022 carries the wrong one).

SELECT release, period, fiscal_quarter, COUNT_BIG(*) AS n
FROM stg.inyear_snapshot
WHERE (period = 0 AND fiscal_quarter IS NOT NULL)
   OR (period BETWEEN 1 AND 12 AND (fiscal_quarter IS NULL OR fiscal_quarter <> (period + 2) / 3))
   OR period > 12
GROUP BY release, period, fiscal_quarter;
