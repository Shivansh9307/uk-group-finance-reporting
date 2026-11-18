-- stg.department_sr_group: typed copy of authored/department_sr_group.csv (read from authored.department_sr_group).
-- It says which Spending Review group a current department belongs to, with organisation exceptions where one
-- department number feeds two groups, and which departments make up the combined pre-2023 group.
--   durable_key  '' = the rule is for the whole department number; otherwise it is an exception for that
--                organisation (the durable key survives code changes and renames)
--   basis        current              used by the outturn bridge (dw.outturn_sr_group_bridge)
--                pre2023_as_reported  the department as a release reported it before the February 2023 reorganisation;
--                                     used only to build the phasing profile of the combined pre-2023 group
-- The build stops here, with a message, when the file breaks a rule. Authored data: it decides which group a line
-- is added to and holds no amount.

DROP TABLE IF EXISTS stg.department_sr_group;
GO

CREATE TABLE stg.department_sr_group (
    department_number  nvarchar(10)   NOT NULL,
    durable_key        nvarchar(30)   NOT NULL,
    basis              varchar(30)    NOT NULL,
    sr_group_code      varchar(20)    NOT NULL,
    evidence           nvarchar(1000) NOT NULL,
    note               nvarchar(1000) NOT NULL,
    load_order         int            NOT NULL,
    CONSTRAINT pk_stg_department_sr_group PRIMARY KEY (department_number, durable_key, basis)
);
GO

INSERT INTO stg.department_sr_group (department_number, durable_key, basis, sr_group_code, evidence, note, load_order)
SELECT LTRIM(RTRIM(department_number)), LTRIM(RTRIM(durable_key)), LTRIM(RTRIM(basis)), LTRIM(RTRIM(sr_group_code)),
       evidence, note, _load_order
FROM authored.department_sr_group;
GO

IF EXISTS (SELECT 1 FROM stg.department_sr_group WHERE basis NOT IN ('current', 'pre2023_as_reported'))
    THROW 50550, 'authored/department_sr_group.csv: basis must be current or pre2023_as_reported', 1;
IF EXISTS (SELECT 1 FROM stg.department_sr_group WHERE evidence = '' OR note = '')
    THROW 50551, 'authored/department_sr_group.csv: every row needs evidence and a note', 1;
IF EXISTS (SELECT 1 FROM stg.department_sr_group AS d
           WHERE NOT EXISTS (SELECT 1 FROM stg.sr_group AS g WHERE g.sr_group_code = d.sr_group_code))
    THROW 50552, 'authored/department_sr_group.csv: an sr_group_code is not a member of authored/sr_group.csv', 1;
IF EXISTS (SELECT 1 FROM stg.department_sr_group AS d
           JOIN stg.sr_group AS g ON g.sr_group_code = d.sr_group_code
           WHERE (d.basis = 'pre2023_as_reported' AND g.member_type <> 'combined_pre_2023')
              OR (d.basis = 'current' AND g.member_type = 'combined_pre_2023'))
    THROW 50553, 'authored/department_sr_group.csv: the combined pre-2023 member is used by basis pre2023_as_reported and by nothing else', 1;
IF EXISTS (SELECT 1 FROM stg.department_sr_group AS e
           WHERE e.durable_key <> '' AND NOT EXISTS (SELECT 1 FROM stg.department_sr_group AS d
                                                     WHERE d.department_number = e.department_number AND d.durable_key = '' AND d.basis = e.basis))
    THROW 50554, 'authored/department_sr_group.csv: an organisation exception needs a department row for the same number and basis', 1;
IF EXISTS (SELECT 1 FROM stg.department_sr_group WHERE basis = 'pre2023_as_reported' AND durable_key <> '')
    THROW 50555, 'authored/department_sr_group.csv: a pre2023_as_reported row is a department row, not an organisation exception', 1;
GO
