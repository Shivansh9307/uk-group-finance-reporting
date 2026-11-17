-- test: each durable key has at most one current version and exactly one latest version, and the current one is the latest
SELECT durable_key, SUM(CAST(is_current AS int)) AS current_versions, SUM(CAST(is_latest_version AS int)) AS latest_versions
FROM dw.dim_organisation
GROUP BY durable_key
HAVING SUM(CAST(is_current AS int)) > 1 OR SUM(CAST(is_latest_version AS int)) <> 1
UNION ALL
SELECT durable_key, 1, 1
FROM dw.dim_organisation
WHERE is_current = 1 AND is_latest_version = 0;
