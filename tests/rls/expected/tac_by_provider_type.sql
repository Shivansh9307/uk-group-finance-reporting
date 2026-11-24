-- Independent of the model: cash and cash equivalents (BAL1240) at the end of 2024-25 and the providers with statements, by
-- provider type, for a user mapped to the department the providers answer to; no row for any other user.
SELECT p.provider_type AS [Provider Type], CAST(SUM(f.value) AS decimal(38, 4)) AS cash, COUNT_BIG(DISTINCT f.provider_key) AS providers_reporting
FROM dw.tac_fact AS f
JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key AND l.sub_code = 'BAL1240'
JOIN dw.tac_provider AS p ON p.provider_key = f.provider_key
WHERE f.period_column = 'CY' AND f.release = '2024-25'
  AND EXISTS (SELECT 1 FROM dw.tac_provider_group AS g
              WHERE g.provider_key = p.provider_key
                AND g.department_number IN (SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user}))
GROUP BY p.provider_type
ORDER BY p.provider_type;
