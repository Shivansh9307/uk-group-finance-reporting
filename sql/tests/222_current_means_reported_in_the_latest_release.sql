-- test: a version is current exactly when it is the key's latest version and the key is reported in the latest release
SELECT o.organisation_key, o.durable_key, o.is_current
FROM dw.dim_organisation AS o
WHERE o.organisation_key > 0
  AND o.is_current <> CASE WHEN o.is_latest_version = 1 AND EXISTS (SELECT 1 FROM stg.organisation_release_key k
                                        WHERE k.durable_key = o.durable_key
                                          AND k.release_seq = (SELECT MAX(release_seq) FROM stg.release))
                           THEN 1 ELSE 0 END;
