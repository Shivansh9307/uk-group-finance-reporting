-- test: a provider is one NHS code; in a year it has one row, of the type of the file it is listed in; the latest name, type, region and sector of a provider are the latest listed year's; the count of data years follows the year rows; every provider-year with data is in the fact
-- marker: localdata
SELECT provider_code, release, COUNT(*) AS n, 'provider listed twice in a year' AS problem
FROM stg.tac_provider_year GROUP BY provider_code, release HAVING COUNT(*) > 1
UNION ALL
SELECT p.provider_code, y.release, NULL, 'year row type or year differs from the file'
FROM dw.tac_provider_year AS y
JOIN dw.tac_provider AS p ON p.provider_key = y.provider_key
JOIN raw.tac_file AS f ON f.file_id = y.file_id
WHERE y.provider_type <> f.provider_type OR y.release <> f.release
UNION ALL
SELECT p.provider_code, NULL, NULL, 'latest type, name, region or sector is not the latest year''s'
FROM dw.tac_provider AS p
JOIN dw.tac_provider_year AS y ON y.provider_key = p.provider_key AND y.release = p.last_listed_release
WHERE y.provider_name <> p.provider_name OR y.provider_type <> p.provider_type OR y.region <> p.region OR y.sector <> p.sector
UNION ALL
SELECT p.provider_code, NULL, p.n_data_years, 'n_data_years differs from the year rows'
FROM dw.tac_provider AS p
WHERE p.n_data_years <> (SELECT COUNT(*) FROM dw.tac_provider_year AS y WHERE y.provider_key = p.provider_key AND y.has_statement_data = 1)
UNION ALL
SELECT p.provider_code, y.release, NULL, 'a provider year with data is not in the fact'
FROM dw.tac_provider_year AS y
JOIN dw.tac_provider AS p ON p.provider_key = y.provider_key
WHERE y.has_statement_data = 1
  AND NOT EXISTS (SELECT 1 FROM dw.tac_fact AS f WHERE f.provider_key = y.provider_key AND f.release = y.release);
