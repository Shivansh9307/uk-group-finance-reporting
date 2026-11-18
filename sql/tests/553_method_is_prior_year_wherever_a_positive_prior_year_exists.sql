-- test: the profile method is recomputed from dw.fact_outturn without the profile code: prior_year_outturn wherever the year-end release of the prior year has a positive total for the profile's lines, flat_prior_not_positive where it has lines with a total of zero or less, flat_no_prior_year otherwise
-- This check covers the group profiles (grains B, C and D) of the current Spending Review groups; the organisation profiles (grain A) and the combined pre-2023 group are checked in test 554.
WITH profiles AS (
    SELECT DISTINCT profile_key, financial_year, prior_financial_year, year_end_release_key, sr_group_key, measure, method
    FROM dw.plan_phasing_profile
    WHERE profile_basis = 'group'
      AND sr_group_key NOT IN (SELECT sr_group_key FROM dw.dim_sr_group WHERE member_type = 'combined_pre_2023')
), lines AS (
    SELECT p.profile_key, SUM(f.amount_delta) AS total, COUNT(*) AS n
    FROM profiles AS p
    JOIN dw.fact_outturn AS f ON f.release_key <= p.year_end_release_key
    JOIN dw.dim_period AS d ON d.period_key = f.period_key AND d.financial_year = p.prior_financial_year AND d.period BETWEEN 1 AND 12
    JOIN dw.dim_segment AS sg ON sg.segment_key = f.segment_key
    JOIN dw.outturn_sr_group_bridge AS b ON b.organisation_key = f.organisation_key AND b.sub_segment_code = sg.sub_segment_code
    JOIN dw.dim_account AS a ON a.account_key = f.account_key
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = f.control_budget_key
    WHERE b.sr_group_key = p.sr_group_key
      AND ((p.measure = 'RDEL_EX_DEPN' AND cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') AND a.economic_budget = 'RESOURCE' AND a.pesa_economic_group_code <> 'DEPRECIATION')
        OR (p.measure = 'CDEL'         AND cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') AND a.economic_budget = 'CAPITAL')
        OR (p.measure = 'RAME'         AND cb.control_budget_detail_code = 'DEPT AME' AND a.economic_budget = 'RESOURCE')
        OR (p.measure = 'CAME'         AND cb.control_budget_detail_code = 'DEPT AME' AND a.economic_budget = 'CAPITAL')
        OR (p.measure = 'ADMIN'        AND cb.control_budget_detail_code = 'DEL ADMIN' AND a.economic_budget = 'RESOURCE')
        OR (p.measure = 'ADMIN_EX_DEPN' AND cb.control_budget_detail_code = 'DEL ADMIN' AND a.economic_budget = 'RESOURCE' AND a.pesa_economic_group_code <> 'DEPRECIATION')
        OR (p.measure = 'RDEL'         AND cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN') AND a.economic_budget = 'RESOURCE'))
    GROUP BY p.profile_key
)
SELECT 'method differs from the recomputation' AS problem, CAST(p.profile_key AS nvarchar(20)) AS detail, p.method AS detail2,
       CASE WHEN p.year_end_release_key IS NULL THEN 'flat_no_prior_year'
            WHEN l.profile_key IS NULL THEN 'flat_no_prior_year'
            WHEN l.total > 0 THEN 'prior_year_outturn' ELSE 'flat_prior_not_positive' END AS expected
FROM profiles AS p
LEFT JOIN lines AS l ON l.profile_key = p.profile_key
WHERE p.method <> CASE WHEN p.year_end_release_key IS NULL THEN 'flat_no_prior_year'
                       WHEN l.profile_key IS NULL THEN 'flat_no_prior_year'
                       WHEN l.total > 0 THEN 'prior_year_outturn' ELSE 'flat_prior_not_positive' END;
