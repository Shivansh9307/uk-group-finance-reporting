-- test: the method of the organisation profiles (plan grain A) and of the combined pre-2023 group profiles is recomputed from dw.fact_outturn at the year-end release of the prior year, without the profile code
WITH org_profiles AS (
    SELECT DISTINCT profile_key, financial_year, prior_financial_year, year_end_release_key, organisation_code, control_budget_detail, economic_budget, method
    FROM dw.plan_phasing_profile WHERE profile_basis = 'organisation'
), org_lines AS (
    SELECT p.profile_key, SUM(f.amount_delta) AS total
    FROM org_profiles AS p
    JOIN dw.dim_organisation AS o ON o.organisation_code = p.organisation_code
    JOIN dw.fact_outturn AS f ON f.organisation_key = o.organisation_key AND f.release_key <= p.year_end_release_key
    JOIN dw.dim_period AS d ON d.period_key = f.period_key AND d.financial_year = p.prior_financial_year AND d.period BETWEEN 1 AND 12
    JOIN dw.dim_account AS a ON a.account_key = f.account_key
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = f.control_budget_key
    WHERE cb.control_budget_detail_code = p.control_budget_detail
      AND CASE WHEN a.economic_budget IN ('RESOURCE', 'CAPITAL') THEN a.economic_budget ELSE 'n/a' END = p.economic_budget
    GROUP BY p.profile_key
), combined AS (
    SELECT DISTINCT p.profile_key, p.prior_financial_year, p.year_end_release_key, p.measure, p.method
    FROM dw.plan_phasing_profile AS p
    JOIN dw.dim_sr_group AS g ON g.sr_group_key = p.sr_group_key AND g.member_type = 'combined_pre_2023'
    WHERE p.profile_basis = 'group'
), combined_lines AS (
    SELECT c.profile_key, SUM(f.amount_delta) AS total
    FROM combined AS c
    JOIN dw.fact_outturn AS f ON f.release_key <= c.year_end_release_key
    JOIN dw.dim_period AS d ON d.period_key = f.period_key AND d.financial_year = c.prior_financial_year AND d.period BETWEEN 1 AND 12
    JOIN dw.dim_department AS dp ON dp.department_key = f.department_key
    JOIN dw.dim_account AS a ON a.account_key = f.account_key
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = f.control_budget_key
    WHERE dp.department_number IN (SELECT department_number FROM authored.department_sr_group WHERE basis = 'pre2023_as_reported')
      AND ((c.measure = 'RDEL_EX_DEPN' AND cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') AND a.economic_budget = 'RESOURCE' AND a.pesa_economic_group_code <> 'DEPRECIATION')
        OR (c.measure = 'CDEL'         AND cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') AND a.economic_budget = 'CAPITAL')
        OR (c.measure = 'RDEL'         AND cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') AND a.economic_budget = 'RESOURCE')
        OR (c.measure = 'RAME'         AND cb.control_budget_detail_code = 'DEPT AME' AND a.economic_budget = 'RESOURCE')
        OR (c.measure = 'CAME'         AND cb.control_budget_detail_code = 'DEPT AME' AND a.economic_budget = 'CAPITAL')
        OR (c.measure = 'ADMIN'        AND cb.control_budget_detail_code = 'DEL ADMIN' AND a.economic_budget = 'RESOURCE')
        OR (c.measure = 'ADMIN_EX_DEPN' AND cb.control_budget_detail_code = 'DEL ADMIN' AND a.economic_budget = 'RESOURCE' AND a.pesa_economic_group_code <> 'DEPRECIATION'))
    GROUP BY c.profile_key
)
SELECT 'organisation profile method differs from the recomputation' AS problem, CAST(p.profile_key AS nvarchar(20)) AS detail, p.method AS detail2
FROM org_profiles AS p
LEFT JOIN org_lines AS l ON l.profile_key = p.profile_key
WHERE p.method <> CASE WHEN p.year_end_release_key IS NULL OR l.profile_key IS NULL THEN 'flat_no_prior_year'
                       WHEN l.total > 0 THEN 'prior_year_outturn' ELSE 'flat_prior_not_positive' END
UNION ALL
SELECT 'combined profile method differs from the recomputation', CAST(p.profile_key AS nvarchar(20)), p.method
FROM combined AS p
LEFT JOIN combined_lines AS l ON l.profile_key = p.profile_key
WHERE p.method <> CASE WHEN p.year_end_release_key IS NULL OR l.profile_key IS NULL THEN 'flat_no_prior_year'
                       WHEN l.total > 0 THEN 'prior_year_outturn' ELSE 'flat_prior_not_positive' END;
