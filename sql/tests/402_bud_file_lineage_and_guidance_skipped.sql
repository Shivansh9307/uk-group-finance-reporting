-- test: 15 BUD workbooks are loaded with matching hashes, every raw row has a loaded file, and the guidance files are recorded as skipped
-- marker: localdata
-- requires: raw.oscar_bud, raw.oscar_bud_file, raw.oscar_bud_control_expected, raw.oscar_bud_independent_expected
SELECT N'hash mismatch' AS problem, f.filename AS detail
FROM raw.oscar_bud_file AS f
JOIN raw.oscar_bud_control_expected AS e ON e.vintage = f.vintage AND e.filename = f.filename
JOIN raw.oscar_bud_independent_expected AS i ON i.vintage = f.vintage AND i.filename = f.filename
WHERE f.file_kind = 'data'
  AND (f.sha256_file <> f.sha256_manifest OR f.sha256_file <> e.sha256 OR f.sha256_file <> i.sha256)
UNION ALL
SELECT N'raw row without a loaded file', CAST(r.file_id AS nvarchar(20))
FROM (SELECT DISTINCT file_id FROM raw.oscar_bud) AS r
WHERE NOT EXISTS (SELECT 1 FROM raw.oscar_bud_file AS f
                  WHERE f.file_id = r.file_id AND f.file_kind = 'data' AND f.load_status = 'loaded')
UNION ALL
SELECT N'data files loaded <> 15', CAST(COUNT(*) AS nvarchar(20))
FROM raw.oscar_bud_file WHERE file_kind = 'data' AND load_status = 'loaded' HAVING COUNT(*) <> 15
UNION ALL
SELECT N'vintages <> 3', CAST(COUNT(DISTINCT vintage) AS nvarchar(20))
FROM raw.oscar_bud_file WHERE file_kind = 'data' HAVING COUNT(DISTINCT vintage) <> 3
UNION ALL
SELECT N'guidance file not recorded as skipped', filename
FROM raw.oscar_bud_file
WHERE file_kind <> 'data' AND (load_status <> 'skipped' OR skip_reason = N'' OR data_rows <> 0)
UNION ALL
SELECT N'guidance files recorded <> 4', CAST(COUNT(*) AS nvarchar(20))
FROM raw.oscar_bud_file WHERE file_kind = 'guidance' HAVING COUNT(*) <> 4;
