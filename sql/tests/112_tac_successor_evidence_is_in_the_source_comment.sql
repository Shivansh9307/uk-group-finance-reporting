-- test: every authored successor row is true to the source: the quoted fragment is in the comment of the named provider in the named year's list of providers, the predecessor exists, the successor exists unless it is not a TAC provider, a provider has one successor, and a predecessor has no data after the year of the change
-- marker: localdata
SELECT s.predecessor_code, 'the quoted fragment is not in the comment of that provider and year' AS problem
FROM stg.tac_provider_successor AS s
WHERE NOT EXISTS (SELECT 1 FROM stg.tac_provider_year AS y
                  WHERE y.provider_code = s.quote_provider_code AND y.release = s.quote_release
                    AND y.comment_text LIKE N'%' + s.quote_fragment + N'%')
UNION ALL
SELECT s.predecessor_code, 'predecessor is not a TAC provider'
FROM stg.tac_provider_successor AS s
WHERE NOT EXISTS (SELECT 1 FROM dw.tac_provider AS p WHERE p.provider_code = s.predecessor_code)
UNION ALL
SELECT s.predecessor_code, 'successor is not a TAC provider and is not the one integrated care board'
FROM stg.tac_provider_successor AS s
WHERE NOT EXISTS (SELECT 1 FROM dw.tac_provider AS p WHERE p.provider_code = s.successor_code)
  AND s.successor_code <> 'QUA'
UNION ALL
SELECT s.predecessor_code, 'the integrated care board has a provider row'
FROM stg.tac_provider_successor AS s
WHERE s.successor_code = 'QUA' AND EXISTS (SELECT 1 FROM dw.tac_provider AS p WHERE p.provider_code = 'QUA')
UNION ALL
SELECT p.provider_code, 'predecessor has data in a year after the change'
FROM dw.tac_provider AS p
JOIN stg.tac_provider_successor AS s ON s.predecessor_code = p.provider_code
WHERE s.effective_date IS NOT NULL
  AND p.last_data_release > CASE WHEN MONTH(s.effective_date) >= 4 THEN CONCAT(YEAR(s.effective_date), '-', RIGHT(CONCAT('0', (YEAR(s.effective_date) + 1) % 100), 2))
                                 ELSE CONCAT(YEAR(s.effective_date) - 1, '-', RIGHT(CONCAT('0', YEAR(s.effective_date) % 100), 2)) END
UNION ALL
SELECT p.provider_code, 'successor columns of the dimension differ from the authored row'
FROM dw.tac_provider AS p
LEFT JOIN stg.tac_provider_successor AS s ON s.predecessor_code = p.provider_code
WHERE ISNULL(p.successor_code, '') <> ISNULL(s.successor_code, '')
   OR ISNULL(p.successor_kind, '') <> ISNULL(s.change_kind, '');
