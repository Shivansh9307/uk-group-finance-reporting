-- Independent of the model: the organisations of the workforce files and how many have a name in their latest version. The
-- organisation dimension is not filtered by department, so every user a role may see it for gets the same two numbers.
SELECT COUNT_BIG(*) AS organisations,
       SUM(CASE WHEN LEN(o.organisation_name) > 0 THEN 1 ELSE 0 END) AS named
FROM dw.dim_organisation AS o
WHERE o.is_latest_version = 1 AND o.durable_key IN (SELECT DISTINCT durable_key FROM dw.workforce_month);
