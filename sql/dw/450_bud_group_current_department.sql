-- scope: full
-- dw.bud_group_current_department: which current department each department group of the annual restated
-- files (BUD) stands for. The annual files are published on the structure of their own release, so a group
-- is a department of the current structure (BIS084.GROUP is DSIT, DEC066.GROUP is DESNZ, UKT013.GROUP is DBT).
-- Rule, in this order:
--   department number   the group's code is the lead organisation's code and '.GROUP'; the last three digits
--                       are a department number, and a number that is a current department (the same
--                       definition as the in-year map, dw.current_structure_department.is_live) is the answer
--   organisation        the lead organisation, found in dw.dim_organisation, goes where the in-year map sends
--                       the organisation as a whole: its home, or its successor's (FCO027.GROUP is the FCO core
--                       in 2020-21 and goes to the Foreign, Commonwealth and Development Office)
--   unallocated         the lead organisation has no home and no successor: the Unallocated member of its
--                       former department, as in-year
--   none                no current department: the group has no organisation in the in-year series (local
--                       government, the Treasury's central exchequer): current_department_key = -1
-- One row per department group code that any vintage holds; the name is the latest vintage's.

DROP TABLE IF EXISTS dw.bud_group_current_department;
GO

CREATE TABLE dw.bud_group_current_department (
    department_group_code    nvarchar(20)  NOT NULL CONSTRAINT pk_dw_bud_group_current_department PRIMARY KEY,
    department_group_name    nvarchar(200) NOT NULL,
    current_department_key   int           NOT NULL,   -- -1 = no current department
    method                   varchar(30)   NOT NULL
);
GO

WITH grp AS (
    SELECT department_group_code,
           MAX(department_group_name) AS department_group_name,
           REPLACE(department_group_code, N'.GROUP', N'') AS lead_code
    FROM stg.bud_department_group_map
    GROUP BY department_group_code
), lead AS (
    SELECT g.department_group_code, g.department_group_name, g.lead_code, RIGHT(g.lead_code, 3) AS number,
           (SELECT TOP (1) x.department_key FROM dw.current_structure_department x
            WHERE x.department_number = RIGHT(g.lead_code, 3) AND x.is_live = 1 AND x.member_type = 'Department'
            ORDER BY x.department_key DESC) AS number_key,
           (SELECT TOP (1) o.durable_key FROM dw.dim_organisation o WHERE o.organisation_code = g.lead_code ORDER BY o.version_no DESC) AS durable_key
    FROM grp AS g
)
INSERT INTO dw.bud_group_current_department
SELECT l.department_group_code, l.department_group_name,
       ISNULL(COALESCE(l.number_key, co.home_department_key, co.successor_department_key, un.department_key), -1),
       CASE WHEN l.number_key IS NOT NULL THEN 'department number'
            WHEN co.home_department_key IS NOT NULL OR co.successor_department_key IS NOT NULL THEN 'organisation'
            WHEN un.department_key IS NOT NULL THEN 'unallocated'
            ELSE 'none' END
FROM lead AS l
LEFT JOIN dw.current_structure_organisation AS co ON co.durable_key = l.durable_key
LEFT JOIN dw.dim_department AS fd ON fd.department_key = co.former_department_key
LEFT JOIN dw.dim_department AS un ON un.member_type = 'Unallocated' AND un.department_number = N'U' + fd.department_number;
GO
