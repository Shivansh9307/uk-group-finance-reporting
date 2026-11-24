-- test: the balance sheet balances for every provider, year and column to within GBP 1,000 (total assets employed BAL1400 equals total taxpayers' and others' equity BAL1500), and audit.tac_sofp_balance lists every pair recomputed from the fact with the class the rule gives; an exception would be a row here
-- marker: localdata
SELECT provider_code, release, period_column, difference, balance_class, 'balance sheet does not balance to within GBP 1,000' AS problem
FROM audit.tac_sofp_balance WHERE balance_class = 'exception'
UNION ALL
SELECT NULL, NULL, NULL, NULL, NULL, 'pairs listed differ from pairs in the fact, or a pair is incomplete'
FROM (SELECT (SELECT COUNT(*) FROM audit.tac_sofp_balance) AS listed,
             (SELECT COUNT(*) FROM (SELECT f.provider_key, f.release, f.period_column
                                    FROM dw.tac_fact AS f JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key
                                    WHERE l.sub_code IN ('BAL1400', 'BAL1500')
                                    GROUP BY f.provider_key, f.release, f.period_column HAVING COUNT(*) = 2) AS q) AS recomputed,
             (SELECT COUNT(*) FROM (SELECT f.provider_key, f.release, f.period_column
                                    FROM dw.tac_fact AS f JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key
                                    WHERE l.sub_code IN ('BAL1400', 'BAL1500')
                                    GROUP BY f.provider_key, f.release, f.period_column HAVING COUNT(*) <> 2) AS q) AS incomplete) AS c
WHERE c.listed <> c.recomputed OR c.incomplete <> 0
UNION ALL
SELECT provider_code, release, period_column, difference, balance_class, 'class or difference does not follow the rule'
FROM audit.tac_sofp_balance
WHERE balance_class <> CASE WHEN total_assets_employed = total_equity THEN 'exact'
                            WHEN ABS(total_assets_employed - total_equity) < 1 THEN 'rounding' ELSE 'exception' END
   OR difference <> total_assets_employed - total_equity;
