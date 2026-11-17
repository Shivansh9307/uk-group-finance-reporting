-- test: the sha256 of every data file, hashed again at load time, equals the manifest and the control table

SELECT f.file_id, f.release, f.filename, f.sha256_file, f.sha256_manifest, e.sha256 AS sha256_control_table
FROM raw.oscar_inyear_file AS f
LEFT JOIN raw.oscar_inyear_control_expected AS e ON e.release = f.release AND e.filename = f.filename
WHERE e.sha256 IS NULL OR f.sha256_file <> f.sha256_manifest OR f.sha256_file <> e.sha256;
