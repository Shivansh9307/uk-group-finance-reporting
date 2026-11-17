-- test: every version has spellings in the alias table, and their release counts add up to the version's reported releases
SELECT o.organisation_key, o.durable_key, o.n_releases_reported, a.total
FROM dw.dim_organisation AS o
LEFT JOIN (SELECT organisation_key, SUM(n_releases) AS total FROM dw.organisation_name_alias GROUP BY organisation_key) AS a
  ON a.organisation_key = o.organisation_key
WHERE o.organisation_key > 0 AND (a.total IS NULL OR a.total <> o.n_releases_reported);
