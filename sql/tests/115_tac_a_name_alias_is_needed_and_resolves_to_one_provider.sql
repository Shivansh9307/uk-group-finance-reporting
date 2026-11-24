-- test: every authored name alias is needed and exact: the provider and year exist, the plain name key of the list does not occur in that file's data, the aliased name does occur there, and no other provider of the file uses it
-- marker: localdata
SELECT a.release, a.provider_code, 'alias for a provider that is not listed that year' AS problem
FROM stg.tac_name_alias AS a
WHERE NOT EXISTS (SELECT 1 FROM stg.tac_provider_year AS y WHERE y.release = a.release AND y.provider_code = a.provider_code)
UNION ALL
SELECT a.release, a.provider_code, 'the list name already matches the data, so the alias is not needed'
FROM stg.tac_name_alias AS a
JOIN stg.tac_provider_year AS y ON y.release = a.release AND y.provider_code = a.provider_code
WHERE EXISTS (SELECT 1 FROM stg.tac_data_name AS n WHERE n.file_id = y.file_id AND n.name_key = y.name_key)
UNION ALL
SELECT a.release, a.provider_code, 'the aliased name is not in the data of that file'
FROM stg.tac_name_alias AS a
JOIN stg.tac_provider_year AS y ON y.release = a.release AND y.provider_code = a.provider_code
WHERE NOT EXISTS (SELECT 1 FROM stg.tac_data_name AS n WHERE n.file_id = y.file_id AND n.name_key = a.data_name_key)
UNION ALL
SELECT CAST(n.file_id AS nvarchar(20)), n.name_key, 'a data name in the files matches no provider of its file'
FROM stg.tac_data_name AS n
WHERE NOT EXISTS (SELECT 1 FROM stg.tac_provider_year AS y WHERE y.file_id = n.file_id AND y.data_name_key = n.name_key)
  AND EXISTS (SELECT 1 FROM stg.tac_value AS v WHERE v.file_id = n.file_id AND v.name_key = n.name_key)
UNION ALL
SELECT release, provider_code, 'more than one alias for a provider and year'
FROM (SELECT release, provider_code FROM stg.tac_name_alias GROUP BY release, provider_code HAVING COUNT(*) > 1) AS d;
