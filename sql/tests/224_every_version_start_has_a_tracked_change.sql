-- test: a version after the first has a tracked change flag, and a flagged row always starts a version
SELECT o.durable_key, o.version_no, o.version_reason
FROM dw.dim_organisation AS o
WHERE o.organisation_key > 0 AND o.version_no > 1 AND o.change_code = 0 AND o.change_department = 0 AND o.change_name = 0
UNION ALL
SELECT r.durable_key, r.version_no, 'flag inside a version'
FROM stg.organisation_version_row AS r
JOIN (SELECT durable_key, version_no, MIN(release_seq) AS first_seq FROM stg.organisation_version_row GROUP BY durable_key, version_no) AS f
  ON f.durable_key = r.durable_key AND f.version_no = r.version_no
WHERE r.release_seq > f.first_seq AND (r.change_code = 1 OR r.change_department = 1 OR r.change_name = 1);
