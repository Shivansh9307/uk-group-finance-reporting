-- Independent of the model: every provider of dw.tac_provider with its latest name, for a user mapped to the department the
-- providers answer to; no row for any other user.
SELECT p.provider_code AS provider_code, p.provider_name AS provider
FROM dw.tac_provider AS p
WHERE EXISTS (SELECT 1 FROM dw.tac_provider_group AS g
              WHERE g.provider_key = p.provider_key
                AND g.department_number IN (SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user}))
ORDER BY p.provider_code;
