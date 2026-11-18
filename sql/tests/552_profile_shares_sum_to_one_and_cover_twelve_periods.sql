-- test: every phasing profile has the periods 1 to 12 once, its shares add up to exactly 1, flat profiles are twelve twelfths (the last one takes the rounding remainder), and every row is flagged derived
SELECT 'profile without periods 1 to 12 once' AS problem, CAST(profile_key AS nvarchar(20)) AS detail
FROM dw.plan_phasing_profile
GROUP BY profile_key
HAVING COUNT(*) <> 12 OR COUNT(DISTINCT period_no) <> 12 OR MIN(period_no) <> 1 OR MAX(period_no) <> 12
UNION ALL
SELECT 'shares do not add up to 1', CAST(profile_key AS nvarchar(20))
FROM dw.plan_phasing_profile
GROUP BY profile_key HAVING SUM(share) <> CAST(1 AS decimal(19, 10))
UNION ALL
SELECT 'flat profile is not twelve twelfths', CAST(profile_key AS nvarchar(20))
FROM dw.plan_phasing_profile
WHERE method <> 'prior_year_outturn' AND period_no < 12 AND share <> CAST(0.0833333333 AS decimal(19, 10))
UNION ALL
SELECT 'flat profile with prior-year figures but no year-end release', CAST(profile_key AS nvarchar(20))
FROM dw.plan_phasing_profile
WHERE method = 'flat_no_prior_year' AND (prior_year_total IS NOT NULL OR prior_period_amount IS NOT NULL)
UNION ALL
SELECT 'row not flagged derived', CAST(profile_key AS nvarchar(20))
FROM dw.plan_phasing_profile WHERE is_derived <> 1
UNION ALL
SELECT 'has_negative_share does not match the shares', CAST(profile_key AS nvarchar(20))
FROM dw.plan_phasing_profile
GROUP BY profile_key
HAVING MAX(CAST(has_negative_share AS int)) <> MAX(CASE WHEN share < 0 THEN 1 ELSE 0 END)
    OR MIN(CAST(has_negative_share AS int)) <> MAX(CAST(has_negative_share AS int))
UNION ALL
SELECT 'method is not one of the three', CAST(profile_key AS nvarchar(20))
FROM dw.plan_phasing_profile
WHERE method NOT IN ('prior_year_outturn', 'flat_no_prior_year', 'flat_prior_not_positive')
UNION ALL
SELECT 'prior-year amounts do not give the shares', CAST(profile_key AS nvarchar(20))
FROM dw.plan_phasing_profile
WHERE method = 'prior_year_outturn' AND period_no < 12
  AND ABS(share - CAST(prior_period_amount AS decimal(28, 10)) / CAST(prior_year_total AS decimal(28, 10))) > CAST(0.00000000005 AS decimal(28, 12));
