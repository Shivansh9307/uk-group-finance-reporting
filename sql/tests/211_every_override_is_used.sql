-- test: every override row is used by at least one organisation code in one release
SELECT o.override_id, o.organisation_code, o.durable_key
FROM stg.organisation_key_override AS o
WHERE NOT EXISTS (SELECT 1 FROM stg.organisation_release_key k WHERE k.override_id = o.override_id);
