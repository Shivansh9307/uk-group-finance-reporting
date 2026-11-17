-- test: a file that is not the primary of its release is proven identical to the primary and has no rows loaded
-- (the March 2026 release is published twice, as a zip holding an ODS and as a bare ODS)

SELECT f.file_id, f.release, f.filename, f.load_status, f.duplicate_of_file_id, f.duplicate_identical,
       (SELECT COUNT_BIG(*) FROM raw.oscar_inyear AS r WHERE r.file_id = f.file_id) AS raw_rows
FROM raw.oscar_inyear_file AS f
WHERE f.primary_for_release = 'N'
  AND (ISNULL(f.duplicate_identical, 0) <> 1
       OR f.load_status <> 'duplicate_of_primary'
       OR f.duplicate_of_file_id IS NULL
       OR EXISTS (SELECT 1 FROM raw.oscar_inyear AS r WHERE r.file_id = f.file_id)
       OR EXISTS (SELECT 1 FROM quarantine.oscar_inyear AS q WHERE q.file_id = f.file_id)
       OR NOT EXISTS (SELECT 1 FROM raw.oscar_inyear_file AS p
                      WHERE p.file_id = f.duplicate_of_file_id AND p.release = f.release
                        AND p.primary_for_release = 'Y' AND p.data_rows = f.data_rows
                        AND p.content_digest = f.content_digest));
