-- test: every TAC provider is linked, once, at department level, to the department key that the organisation dimension gives the Department of Health and Social Care (the key of the current DOH033 organisation line), and to no other
-- marker: localdata
SELECT p.provider_code, 'provider without a group link' AS problem
FROM dw.tac_provider AS p
LEFT JOIN dw.tac_provider_group AS g ON g.provider_key = p.provider_key
WHERE g.provider_key IS NULL
UNION ALL
SELECT CAST(g.provider_key AS nvarchar(20)), 'link is not to the department key of DOH033 in the organisation dimension'
FROM dw.tac_provider_group AS g
WHERE g.department_key NOT IN (SELECT o.department_key FROM dw.dim_organisation AS o WHERE o.durable_key = 'DOH033' AND o.is_current = 1)
   OR g.department_key NOT IN (SELECT d.department_key FROM dw.dim_department AS d WHERE d.department_number = g.department_number)
   OR g.link_level <> 'department'
UNION ALL
SELECT NULL, 'the organisation dimension has no single current DOH033 version'
WHERE (SELECT COUNT(*) FROM dw.dim_organisation WHERE durable_key = 'DOH033' AND is_current = 1) <> 1
UNION ALL
SELECT CAST(COUNT(DISTINCT department_key) AS nvarchar(20)), 'more than one department key in the links'
FROM dw.tac_provider_group HAVING COUNT(DISTINCT department_key) > 1;
