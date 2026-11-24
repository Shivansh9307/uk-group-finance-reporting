-- Independent of the model: the TAC accounts are visible to a user mapped to the department of the providers (the
-- Department of Health and Social Care, number 033 in dw.tac_provider_group); for any other user, or none, there is
-- nothing: amounts NULL, row counts 0. Cash is BAL1240, the derived cash flow is added over all its lines, the
-- consolidated cash is the printed GBP million times 1,000.
WITH dept AS (
    SELECT DISTINCT g.department_number FROM dw.tac_provider_group AS g
    WHERE g.department_number IN (SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user})
),
seen AS (SELECT CASE WHEN EXISTS (SELECT 1 FROM dept) THEN 1 ELSE 0 END AS can_see)
SELECT
    CAST(CASE WHEN s.can_see = 1 THEN (SELECT SUM(f.value) FROM dw.tac_fact AS f JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key AND l.sub_code = 'BAL1240'
                                       WHERE f.period_column = 'CY' AND f.release = '2024-25') END AS decimal(38, 4)) AS cash_2024_25,
    CASE WHEN s.can_see = 1 THEN (SELECT COUNT_BIG(DISTINCT f.provider_key) FROM dw.tac_fact AS f WHERE f.period_column = 'CY' AND f.release = '2024-25') END AS providers_reporting_2024_25,
    CAST(CASE WHEN s.can_see = 1 THEN (SELECT SUM(d.amount) FROM dw.tac_cash_flow_derived AS d WHERE d.release = '2024-25') END AS decimal(38, 4)) AS derived_net_change_2024_25,
    CAST(CASE WHEN s.can_see = 1 THEN (SELECT SUM(c.amount_gbp_million) * 1000 FROM dw.tac_consolidated_control AS c WHERE c.release = '2024-25' AND c.printed_line = 'CASH_AND_CASH_EQUIVALENTS') END AS decimal(38, 4)) AS consolidated_cash_2024_25,
    CAST(CASE WHEN s.can_see = 1 THEN (SELECT SUM(f.value) FROM dw.tac_fact AS f JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key AND l.sub_code = 'BAL1240'
                                       WHERE f.period_column = 'CY' AND f.release = '2024-25')
                                      - (SELECT SUM(c.amount_gbp_million) * 1000 FROM dw.tac_consolidated_control AS c WHERE c.release = '2024-25' AND c.printed_line = 'CASH_AND_CASH_EQUIVALENTS') END AS decimal(38, 4)) AS gap_cash_2024_25,
    CASE WHEN s.can_see = 1 THEN (SELECT COUNT_BIG(*) FROM dw.tac_provider) ELSE 0 END AS provider_rows,
    CASE WHEN s.can_see = 1 THEN (SELECT COUNT_BIG(*) FROM dw.tac_fact) ELSE 0 END AS fact_rows,
    CASE WHEN s.can_see = 1 THEN (SELECT COUNT_BIG(*) FROM dw.tac_consolidated_control) ELSE 0 END AS consolidated_rows
FROM seen AS s;
