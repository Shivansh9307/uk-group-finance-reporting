-- test: a name change to a name seen before, or away from a name that comes back, is an alias and starts no version
SELECT r.durable_key, r.release_seq, r.name_norm
FROM stg.organisation_version_row AS r
WHERE r.change_name = 1
  AND (EXISTS (SELECT 1 FROM stg.organisation_version_row x
               WHERE x.durable_key = r.durable_key AND x.release_seq < r.release_seq AND x.name_norm = r.name_norm)
       OR EXISTS (SELECT 1 FROM stg.organisation_version_row x
                  WHERE x.durable_key = r.durable_key AND x.release_seq > r.release_seq
                    AND x.name_norm = (SELECT TOP (1) p.name_norm FROM stg.organisation_version_row p
                                       WHERE p.durable_key = r.durable_key AND p.release_seq < r.release_seq
                                       ORDER BY p.release_seq DESC)));
