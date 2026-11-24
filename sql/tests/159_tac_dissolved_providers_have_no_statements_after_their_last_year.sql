-- test: for every provider linked to a successor in authored/tac_provider_successor.csv, the statements stop at the year that contains the effective date or ends the day before it (a provider acquired on 1 April stops with the year to 31 March), a provider with a successor has no current-year value in any later file, and the 18 predecessors whose last statements are before the latest year are exactly those the dissolved-provider test of the model uses
-- marker: localdata
-- requires: dw.tac_provider
SELECT p.provider_code AS what, 'last statements are not the year that contains, or ends the day before, the effective date' AS problem
FROM dw.tac_provider AS p
WHERE p.successor_effective_date IS NOT NULL AND p.last_data_release IS NOT NULL
  AND NOT (p.successor_effective_date >= DATEFROMPARTS(CAST(LEFT(p.last_data_release, 4) AS int), 4, 1)
       AND p.successor_effective_date <= DATEFROMPARTS(CAST(LEFT(p.last_data_release, 4) AS int) + 1, 4, 1))
UNION ALL
SELECT p.provider_code, 'current-year value after the last statements'
FROM dw.tac_provider AS p
WHERE p.successor_code IS NOT NULL AND EXISTS (SELECT 1 FROM dw.tac_fact AS f WHERE f.provider_key = p.provider_key AND f.period_column = 'CY' AND f.release > p.last_data_release)
UNION ALL
SELECT 'predecessors', 'the number of predecessors whose last statements are before the latest year is not 18'
WHERE (SELECT COUNT(*) FROM dw.tac_provider AS p WHERE p.successor_code IS NOT NULL AND p.last_data_release < (SELECT MAX(release) FROM dw.tac_fact)) <> 18
UNION ALL
SELECT p.provider_code, 'last data release does not equal the last year with a current-year value'
FROM dw.tac_provider AS p
WHERE p.last_data_release <> (SELECT MAX(f.release) FROM dw.tac_fact AS f WHERE f.provider_key = p.provider_key AND f.period_column = 'CY')
   OR (p.last_data_release IS NULL AND EXISTS (SELECT 1 FROM dw.tac_fact AS f WHERE f.provider_key = p.provider_key));
