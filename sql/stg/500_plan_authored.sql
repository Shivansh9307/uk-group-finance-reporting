-- Typed copies of the three authored plan files, read from the text tables the authored stage loads
-- (authored.plan_name_map, authored.sr_group, authored.plan_source). The build stops here, with a message,
-- when a file breaks a rule: a duplicate key, a value outside its list, a map target that is not a member of
-- the Spending Review group list, a family or edition that does not exist.
-- These tables are authored: they decide which group a published plan line belongs to and describe each
-- plan source. They hold no amounts.

DROP TABLE IF EXISTS stg.plan_name_map;
DROP TABLE IF EXISTS stg.plan_source;
DROP TABLE IF EXISTS stg.sr_group;
GO

CREATE TABLE stg.sr_group (
    sr_group_code    varchar(20)    NOT NULL CONSTRAINT pk_stg_sr_group PRIMARY KEY,
    sr_group_name    nvarchar(200)  NOT NULL CONSTRAINT uq_stg_sr_group_name UNIQUE,
    member_type      varchar(30)    NOT NULL,
    description      nvarchar(1000) NOT NULL,
    evidence         nvarchar(1000) NOT NULL,
    note             nvarchar(1000) NOT NULL,
    load_order       int            NOT NULL
);
GO

INSERT INTO stg.sr_group (sr_group_code, sr_group_name, member_type, description, evidence, note, load_order)
SELECT LTRIM(RTRIM(sr_group_code)), LTRIM(RTRIM(sr_group_name)), LTRIM(RTRIM(member_type)), description, evidence, note, _load_order
FROM authored.sr_group;
GO

IF EXISTS (SELECT 1 FROM stg.sr_group WHERE member_type NOT IN ('spending_review_group', 'plan_only', 'non_department', 'combined_pre_2023'))
    THROW 50001, 'authored/sr_group.csv: member_type must be spending_review_group, plan_only, non_department or combined_pre_2023', 1;
IF EXISTS (SELECT 1 FROM stg.sr_group WHERE evidence = '' OR note = '')
    THROW 50002, 'authored/sr_group.csv: every row needs evidence and a note', 1;
GO

CREATE TABLE stg.plan_name_map (
    name_family   varchar(20)    NOT NULL,
    plan_name     nvarchar(400)  NOT NULL,
    target_type   varchar(30)    NOT NULL,
    target_name   nvarchar(200)  NOT NULL,
    line_role     varchar(20)    NOT NULL,
    confidence    varchar(10)    NOT NULL,
    evidence      nvarchar(1000) NOT NULL,
    note          nvarchar(1000) NOT NULL,
    load_order    int            NOT NULL,
    CONSTRAINT pk_stg_plan_name_map PRIMARY KEY (name_family, plan_name)
);
GO

INSERT INTO stg.plan_name_map (name_family, plan_name, target_type, target_name, line_role, confidence, evidence, note, load_order)
SELECT LTRIM(RTRIM(name_family)), LTRIM(RTRIM(plan_name)), LTRIM(RTRIM(target_type)), LTRIM(RTRIM(target_name)),
       LTRIM(RTRIM(line_role)), LTRIM(RTRIM(confidence)), evidence, note, _load_order
FROM authored.plan_name_map;
GO

IF EXISTS (SELECT 1 FROM stg.plan_name_map WHERE name_family NOT IN ('hmt_tables', 'oscar_extract'))
    THROW 50003, 'authored/plan_name_map.csv: name_family must be hmt_tables or oscar_extract', 1;
IF EXISTS (SELECT 1 FROM stg.plan_name_map WHERE line_role NOT IN ('whole', 'part', 'component'))
    THROW 50004, 'authored/plan_name_map.csv: line_role must be whole, part or component', 1;
IF EXISTS (SELECT 1 FROM stg.plan_name_map WHERE confidence NOT IN ('high', 'medium', 'low'))
    THROW 50005, 'authored/plan_name_map.csv: confidence must be high, medium or low', 1;
IF EXISTS (SELECT 1 FROM stg.plan_name_map AS m
           WHERE NOT EXISTS (SELECT 1 FROM stg.sr_group AS g WHERE g.sr_group_name = m.target_name AND g.member_type = m.target_type))
    THROW 50006, 'authored/plan_name_map.csv: a target_name is not a member of authored/sr_group.csv with the same type', 1;
IF EXISTS (SELECT 1 FROM stg.plan_name_map WHERE evidence = '' OR note = '')
    THROW 50007, 'authored/plan_name_map.csv: every row needs evidence and a note', 1;
GO

CREATE TABLE stg.plan_source (
    plan_source_code     varchar(40)    NOT NULL CONSTRAINT pk_stg_plan_source PRIMARY KEY,
    family               varchar(20)    NOT NULL,
    edition              varchar(30)    NOT NULL,
    edition_label        nvarchar(200)  NOT NULL,
    edition_seq          int            NOT NULL,
    grain_description    nvarchar(400)  NOT NULL,
    plan_basis           nvarchar(200)  NOT NULL,
    includes_block_grant_adjustment varchar(30) NOT NULL,
    scotland_bga_flag    varchar(30)    NOT NULL,
    scotland_bga_rule    nvarchar(1000) NOT NULL,
    resource_basis       varchar(20)    NOT NULL,
    resource_basis_evidence nvarchar(1000) NOT NULL,
    evidence             nvarchar(1000) NOT NULL,
    note                 nvarchar(1000) NOT NULL,
    load_order           int            NOT NULL
);
GO

INSERT INTO stg.plan_source
    (plan_source_code, family, edition, edition_label, edition_seq, grain_description, plan_basis,
     includes_block_grant_adjustment, scotland_bga_flag, scotland_bga_rule, resource_basis, resource_basis_evidence,
     evidence, note, load_order)
SELECT LTRIM(RTRIM(plan_source_code)), LTRIM(RTRIM(family)), LTRIM(RTRIM(edition)), edition_label,
       CAST(LTRIM(RTRIM(edition_seq)) AS int), grain_description, plan_basis,
       LTRIM(RTRIM(includes_block_grant_adjustment)), LTRIM(RTRIM(scotland_bga_flag)), scotland_bga_rule,
       LTRIM(RTRIM(resource_basis)), resource_basis_evidence, evidence, note, _load_order
FROM authored.plan_source;
GO

IF EXISTS (SELECT 1 FROM stg.plan_source WHERE family NOT IN ('oscar_extract', 'estimates', 'pesa', 'sr25'))
    THROW 50008, 'authored/plan_source.csv: family must be oscar_extract, estimates, pesa or sr25', 1;
IF EXISTS (SELECT 1 FROM stg.plan_source WHERE scotland_bga_flag NOT IN ('net_of_bga', 'gross_of_bga', 'same_as_oscar_outturn', 'not_applicable'))
    THROW 50009, 'authored/plan_source.csv: scotland_bga_flag is not one of the four allowed values', 1;
IF EXISTS (SELECT 1 FROM stg.plan_source WHERE resource_basis NOT IN ('as_titled', 'ex_depreciation'))
    THROW 50010, 'authored/plan_source.csv: resource_basis must be as_titled or ex_depreciation', 1;
IF EXISTS (SELECT 1 FROM stg.plan_source WHERE evidence = '' OR note = '')
    THROW 50011, 'authored/plan_source.csv: every row needs evidence and a note', 1;
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'AUTHORED: typed copy of authored/sr_group.csv. Holds no amounts.',
    @level0type = N'SCHEMA', @level0name = N'stg', @level1type = N'TABLE', @level1name = N'sr_group';
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'AUTHORED: typed copy of authored/plan_name_map.csv. Decides which Spending Review group a published plan line belongs to. Holds no amounts.',
    @level0type = N'SCHEMA', @level0name = N'stg', @level1type = N'TABLE', @level1name = N'plan_name_map';
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'AUTHORED: typed copy of authored/plan_source.csv. Describes each plan source and edition. Holds no amounts.',
    @level0type = N'SCHEMA', @level0name = N'stg', @level1type = N'TABLE', @level1name = N'plan_source';
GO
