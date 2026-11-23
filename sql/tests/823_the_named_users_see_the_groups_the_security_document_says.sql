-- test: the invented users see the plan groups docs/security.md lists: Health (NHS) for the two-department NHS user, the Defra, Transport and HM Treasury groups for their single-department users, both CLG groups for the user of department 085, the combined pre-2023 group and its three current groups for the three-department user, and no group for the Cabinet Office user and the Parliamentary Works Grant user
WITH expected (user_principal_name, sr_group_code) AS (
    SELECT * FROM (VALUES
        (N'alice.morgan@example.org', 'SR_003'),
        (N'ben.okafor@example.org', 'SR_004'),
        (N'chloe.patel@example.org', 'SR_NHS'),
        (N'george.evans@example.org', 'SR_087'),
        (N'hannah.price@example.org', 'SR_COM'),
        (N'hannah.price@example.org', 'SR_LGV'),
        (N'jasmine.reid@example.org', 'COMBINED_PRE2023'),
        (N'jasmine.reid@example.org', 'SR_013'),
        (N'jasmine.reid@example.org', 'SR_048'),
        (N'jasmine.reid@example.org', 'SR_084')) AS v (user_principal_name, sr_group_code)
), actual AS (
    SELECT v.user_principal_name, g.sr_group_code
    FROM dw.v_model_user_plan_group AS v JOIN dw.dim_sr_group AS g ON g.sr_group_key = v.sr_group_key
)
SELECT 'listed and not visible' AS problem, e.user_principal_name, e.sr_group_code
FROM expected AS e
WHERE NOT EXISTS (SELECT 1 FROM actual AS a WHERE a.user_principal_name = e.user_principal_name AND a.sr_group_code = e.sr_group_code)
UNION ALL
SELECT 'visible and not listed', a.user_principal_name, a.sr_group_code
FROM actual AS a
WHERE NOT EXISTS (SELECT 1 FROM expected AS e WHERE a.user_principal_name = e.user_principal_name AND a.sr_group_code = e.sr_group_code);
