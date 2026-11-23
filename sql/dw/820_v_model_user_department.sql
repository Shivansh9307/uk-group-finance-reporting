-- The model's view layer, part 8: the two tables that drive the row-level security roles.
--   dw.v_model_user_department  one row per invented user and department (its key) of the current structure the user may see
--   dw.v_model_user_plan_group  one row per user and Spending Review group whose plan the user may see
-- Both are read from synthetic.user_department (SYNTHETIC: invented users, no amount) and by nothing else; no fact,
-- no view of a fact and no real total reads either of them (sql/tests/820 and pipeline/tests/test_register.py).
--
-- The department rows are the user's departments, by number, joined to the live departments of the current structure
-- (the same rows as dw.v_model_department). A number that is not a live department of type Department stops the build,
-- so a typo can never give a user fewer rows without a sign.
--
-- The plan is published by Spending Review group, not by department, so a department filter does not reach it. The
-- rule I chose: a user sees the plan of a group only when every department of that group is one of the user's
-- departments. The members of a group are the department numbers of authored/department_sr_group.csv for the group
-- (basis current, or pre2023_as_reported for the combined pre-2023 group). A group with no department member (a
-- reserve, the Single Intelligence Account, the central lines) is never visible. This never shows a user the plan of a
-- department the user cannot see; the cost is that a user for part of a large group sees outturn and no plan.

DROP VIEW IF EXISTS dw.v_model_user_plan_group;
GO
DROP VIEW IF EXISTS dw.v_model_user_department;
GO

DECLARE @bad nvarchar(2000) = (
    SELECT STRING_AGG(CONCAT(u.user_principal_name, ' -> ', u.department_number), N'; ')
    FROM synthetic.user_department AS u
    WHERE NOT EXISTS (SELECT 1
                      FROM dw.dim_department AS d
                      JOIN dw.current_structure_department AS c ON c.department_key = d.department_key AND c.is_live = 1
                      WHERE d.department_number = u.department_number AND d.member_type = 'Department'));
IF @bad IS NOT NULL
BEGIN
    DECLARE @msg nvarchar(2100) = N'synthetic/user_department.csv names a department number that is not a live department of the current structure: ' + @bad;
    THROW 50820, @msg, 1;
END
GO

CREATE VIEW dw.v_model_user_department
AS
SELECT u.user_principal_name, d.department_key
FROM synthetic.user_department AS u
JOIN dw.dim_department AS d ON d.department_number = u.department_number AND d.member_type = 'Department'
JOIN dw.current_structure_department AS c ON c.department_key = d.department_key AND c.is_live = 1;
GO

CREATE VIEW dw.v_model_user_plan_group
AS
WITH members AS (
    SELECT DISTINCT g.sr_group_key, r.department_number
    FROM stg.department_sr_group AS r
    JOIN dw.dim_sr_group AS g ON g.sr_group_code = r.sr_group_code
    WHERE r.basis IN ('current', 'pre2023_as_reported')
), needed AS (
    SELECT sr_group_key, COUNT(*) AS n FROM members GROUP BY sr_group_key
), held AS (
    SELECT u.user_principal_name, m.sr_group_key, COUNT(*) AS n
    FROM synthetic.user_department AS u
    JOIN members AS m ON m.department_number = u.department_number
    GROUP BY u.user_principal_name, m.sr_group_key
)
SELECT h.user_principal_name, h.sr_group_key
FROM held AS h
JOIN needed AS n ON n.sr_group_key = h.sr_group_key AND n.n = h.n;
GO
