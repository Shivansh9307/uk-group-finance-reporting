-- test: within one workbook an organisation has one SR group and one department group, so (vintage, year, organisation) is the key of stg.bud_sr_group_by_organisation
-- marker: localdata
-- requires: raw.oscar_bud, stg.bud_sr_group_by_organisation
SELECT N'organisation with more than one SR or department group in a workbook' AS problem,
       CONCAT(vintage, N' ', year_no, N' ', organisation_code) AS detail
FROM raw.oscar_bud
GROUP BY vintage, year_no, organisation_code
HAVING COUNT(DISTINCT sr_group_code) > 1 OR COUNT(DISTINCT department_group_code) > 1
UNION ALL
SELECT N'map rows <> organisations in the workbooks', CONCAT(m.n, N' vs ', r.n)
FROM (SELECT COUNT(*) AS n FROM stg.bud_sr_group_by_organisation) AS m
CROSS JOIN (SELECT COUNT(*) AS n FROM (SELECT DISTINCT vintage, year_no, organisation_code FROM raw.oscar_bud) AS d) AS r
WHERE m.n <> r.n;
