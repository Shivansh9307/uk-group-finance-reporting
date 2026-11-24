-- test: no TAC row is rejected at load or left out of the fact; every fact row has a provider and a line, and the fact has as many rows as the staged values
-- marker: localdata
SELECT 'rejected at load' AS what, COUNT(*) AS n FROM quarantine.tac_value HAVING COUNT(*) > 0
UNION ALL
SELECT 'unmapped (' + reason_code + ')', COUNT(*) FROM quarantine.tac_unmapped_row GROUP BY reason_code
UNION ALL
SELECT 'fact rows without a provider', COUNT(*) FROM dw.tac_fact AS f
WHERE NOT EXISTS (SELECT 1 FROM dw.tac_provider AS p WHERE p.provider_key = f.provider_key) HAVING COUNT(*) > 0
UNION ALL
SELECT 'fact rows without a line', COUNT(*) FROM dw.tac_fact AS f
WHERE NOT EXISTS (SELECT 1 FROM dw.tac_statutory_line AS l WHERE l.line_key = f.line_key) HAVING COUNT(*) > 0
UNION ALL
SELECT 'fact rows differ from staged rows', (SELECT COUNT(*) FROM stg.tac_value) - (SELECT COUNT(*) FROM dw.tac_fact)
HAVING (SELECT COUNT(*) FROM stg.tac_value) <> (SELECT COUNT(*) FROM dw.tac_fact);
