-- test: the TAC files are exactly six financial years, FY2019-20 to FY2024-25, each with one NHS trust file, one NHS foundation trust file and one illustrative form, and every file matches the manifest hash
-- marker: localdata
SELECT release, SUM(CASE WHEN provider_type = 'NHS trust' THEN 1 ELSE 0 END) AS trust_files,
       SUM(CASE WHEN provider_type = 'NHS foundation trust' THEN 1 ELSE 0 END) AS foundation_files,
       SUM(CASE WHEN file_kind = 'template' THEN 1 ELSE 0 END) AS forms, 'a year does not have one file of each kind' AS problem
FROM raw.tac_file
GROUP BY release
HAVING SUM(CASE WHEN provider_type = 'NHS trust' THEN 1 ELSE 0 END) <> 1
    OR SUM(CASE WHEN provider_type = 'NHS foundation trust' THEN 1 ELSE 0 END) <> 1
    OR SUM(CASE WHEN file_kind = 'template' THEN 1 ELSE 0 END) <> 1
UNION ALL
SELECT NULL, COUNT(DISTINCT release), NULL, NULL, 'expected six years'
FROM raw.tac_file HAVING COUNT(DISTINCT release) <> 6
UNION ALL
SELECT filename, NULL, NULL, NULL, 'file hash differs from the manifest'
FROM raw.tac_file WHERE sha256_file <> sha256_manifest;
