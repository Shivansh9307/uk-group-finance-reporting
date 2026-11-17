-- test: in one release a durable key is carried by one organisation code only, apart from a merged coding error
SELECT durable_key, release_seq, COUNT(*) AS codes
FROM stg.organisation_release_key
WHERE is_merged_code = 0
GROUP BY durable_key, release_seq
HAVING COUNT(*) > 1;
