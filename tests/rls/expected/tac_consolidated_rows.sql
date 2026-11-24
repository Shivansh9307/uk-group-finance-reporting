-- Independent of the model: the 48 hand-keyed values of dw.tac_consolidated_control, for a user mapped to the department the
-- providers answer to; no row for any other user.
SELECT c.release AS financial_year, c.printed_line AS printed_code, c.amount_gbp_million AS printed_amount_gbp_million
FROM dw.tac_consolidated_control AS c
WHERE EXISTS (SELECT 1 FROM dw.tac_provider_group AS g
              WHERE g.department_number IN (SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user}))
ORDER BY c.release, c.printed_line;
