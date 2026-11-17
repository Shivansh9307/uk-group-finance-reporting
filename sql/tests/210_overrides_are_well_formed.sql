-- test: each override has a key, runs forwards, uses a known reason, and no two overrides cover one code in one release
SELECT o.override_id, o.organisation_code, 'bad range, key or reason' AS problem
FROM stg.organisation_key_override AS o
WHERE o.valid_from_seq > o.valid_to_seq OR LEN(o.durable_key) = 0
   OR o.reason NOT IN ('prefix_collision', 'prefix_change', 'reused_code', 'coding_error', 'merger')
UNION ALL
SELECT a.override_id, a.organisation_code, 'overlaps override ' + CAST(b.override_id AS varchar(10))
FROM stg.organisation_key_override AS a
JOIN stg.organisation_key_override AS b
  ON b.organisation_code = a.organisation_code AND b.override_id > a.override_id
 AND b.valid_from_seq <= a.valid_to_seq AND a.valid_from_seq <= b.valid_to_seq;
