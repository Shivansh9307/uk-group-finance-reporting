-- test: the versions of a durable key start at its first release, run forwards, and each starts the release after the previous one ends
SELECT durable_key, version_no, valid_from_release_seq, valid_to_release_seq, 'gap or overlap or backwards range' AS problem
FROM (
    SELECT o.durable_key, o.version_no, o.valid_from_release_seq, o.valid_to_release_seq,
           LAG(o.valid_to_release_seq) OVER (PARTITION BY o.durable_key ORDER BY o.version_no) AS prev_to,
           (SELECT MIN(r.release_seq) FROM stg.organisation_version_row r WHERE r.durable_key = o.durable_key) AS key_first
    FROM dw.dim_organisation AS o
    WHERE o.organisation_key > 0
) AS x
WHERE valid_from_release_seq > valid_to_release_seq
   OR (prev_to IS NOT NULL AND valid_from_release_seq <> prev_to + 1)
   OR (prev_to IS NULL AND valid_from_release_seq <> key_first);
