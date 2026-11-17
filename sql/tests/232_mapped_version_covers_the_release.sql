-- test: the version a release maps to belongs to the durable key, covers that release, and has the code itself unless it is a merged code
SELECT m.release, m.organisation_code, m.organisation_key, o.valid_from_release_seq, o.valid_to_release_seq
FROM dw.organisation_release_map AS m
JOIN dw.dim_organisation AS o ON o.organisation_key = m.organisation_key
JOIN stg.organisation_release_key AS k ON k.release_seq = m.release_seq AND k.organisation_code = m.organisation_code
WHERE o.durable_key <> m.durable_key
   OR m.release_seq NOT BETWEEN o.valid_from_release_seq AND o.valid_to_release_seq
   OR (k.is_merged_code = 0 AND o.organisation_code <> m.organisation_code);
