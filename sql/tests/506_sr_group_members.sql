-- test: dw.dim_sr_group holds the 23 Spending Review groups with the names of the latest BUD, the Single Intelligence Account as plan-only, one combined pre-2023 member, the non-department members and one outturn-only member with outturn and no plan row
WITH expected(name) AS (
    SELECT n FROM (VALUES
        (N'Business and Trade'), (N'Cabinet Office'), (N'CLG Communities'), (N'CLG Local Government'),
        (N'Culture, Media and Sport'), (N'Defence'), (N'Education'), (N'Energy Security and Net Zero'),
        (N'Environment, Food and Rural Affairs'), (N'Foreign, Commonwealth and Development Office'),
        (N'Health (NHS)'), (N'HM Revenue & Customs'), (N'HM Treasury'), (N'Home Office'), (N'Justice'),
        (N'Law Officer''s Departments'), (N'Northern Ireland'), (N'Science, Innovation and Technology'),
        (N'Scotland'), (N'Small and Independent Bodies'), (N'Transport'), (N'Wales'), (N'Work and Pensions')
    ) AS v(n)
)
SELECT e.name AS sr_group_name, 'expected group is missing or has another type' AS problem
FROM expected AS e
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_sr_group AS g
                  WHERE g.sr_group_name = e.name AND g.member_type = 'spending_review_group' AND g.is_department_group = 1)
UNION ALL
SELECT g.sr_group_name, 'department group that is not one of the 23'
FROM dw.dim_sr_group AS g
WHERE g.member_type = 'spending_review_group' AND g.sr_group_name NOT IN (SELECT name FROM expected)
UNION ALL
SELECT 'Single Intelligence Account', 'must be exactly one plan_only member without outturn'
WHERE (SELECT COUNT(*) FROM dw.dim_sr_group WHERE member_type = 'plan_only' AND sr_group_name = N'Single Intelligence Account' AND has_outturn = 0) <> 1
   OR (SELECT COUNT(*) FROM dw.dim_sr_group WHERE member_type = 'plan_only') <> 1
UNION ALL
SELECT 'combined pre-2023', 'must be exactly one combined_pre_2023 member'
WHERE (SELECT COUNT(*) FROM dw.dim_sr_group WHERE member_type = 'combined_pre_2023') <> 1
UNION ALL
SELECT 'outturn-only', 'must be exactly one outturn_only member, with outturn, not a department group and with no plan row'
WHERE (SELECT COUNT(*) FROM dw.dim_sr_group WHERE member_type = 'outturn_only' AND has_outturn = 1 AND is_department_group = 0) <> 1
   OR (SELECT COUNT(*) FROM dw.dim_sr_group WHERE member_type = 'outturn_only') <> 1
   OR EXISTS (SELECT 1 FROM dw.fact_plan AS p JOIN dw.dim_sr_group AS g ON g.sr_group_key = p.sr_group_key WHERE g.member_type = 'outturn_only')
   OR EXISTS (SELECT 1 FROM stg.plan_name_map AS m JOIN dw.dim_sr_group AS g ON g.sr_group_name = m.target_name WHERE g.member_type = 'outturn_only')
UNION ALL
SELECT 'non-department', 'expected at least one non_department member and none flagged as a department group'
WHERE (SELECT COUNT(*) FROM dw.dim_sr_group WHERE member_type = 'non_department') < 5
   OR EXISTS (SELECT 1 FROM dw.dim_sr_group WHERE member_type <> 'spending_review_group' AND is_department_group = 1);
