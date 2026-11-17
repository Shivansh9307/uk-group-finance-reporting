-- test: in raw data a release publishes one organisation name and one department label per organisation code
SELECT release, organisation_code, COUNT(DISTINCT organisation_name) AS names, COUNT(DISTINCT department_name) AS labels
FROM raw.oscar_inyear
GROUP BY release, organisation_code
HAVING COUNT(DISTINCT organisation_name) > 1 OR COUNT(DISTINCT department_name) > 1;
