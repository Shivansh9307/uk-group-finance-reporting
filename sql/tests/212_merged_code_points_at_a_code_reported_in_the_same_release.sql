-- test: a code that merges into another is reported together with it in the same release and shares its durable key
SELECT k.release_seq, k.organisation_code, k.effective_code
FROM stg.organisation_release_key AS k
WHERE k.is_merged_code = 1
  AND NOT EXISTS (SELECT 1 FROM stg.organisation_release_key t
                  WHERE t.release_seq = k.release_seq AND t.organisation_code = k.effective_code
                    AND t.durable_key = k.durable_key AND t.is_merged_code = 0);
