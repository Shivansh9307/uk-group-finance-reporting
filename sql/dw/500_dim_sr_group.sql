-- dw.dim_sr_group: the Spending Review groups that plans are published for.
--   23 groups with the names exactly as the latest annual BUD release writes them (SR_GROUP_LONG_NAME,
--   BUD_24-25.xlsx, November 2025), the Single Intelligence Account (plan only: OSCAR publishes no outturn
--   for it), the combined BEIS, DCMS and DIT group that FY2022-23 plans can only be shown at, and one member
--   per kind of line that is not a department (reserves, the OBR allowance, the Budget Exchange adjustment,
--   unallocated central funds, memo and accounting lines), and one outturn-only member for the lines of closed or
--   split departments that no current department took over (no plan is published for it).
-- The members and their descriptions are authored (authored/sr_group.csv, typed in stg.sr_group); the key is a plain row number in
-- a fixed order: departments by name, then plan-only, combined, then the non-department members by name, then the
-- outturn-only member.
-- Authored, not real data: this table decides which group a published plan line is added to. It holds no
-- amounts, so it cannot reach a real total.

-- The tables that point at the dimensions are dropped first, so the build can run again on an existing database.
DROP TABLE IF EXISTS dw.plan_coverage;
DROP TABLE IF EXISTS dw.fact_plan;
DROP TABLE IF EXISTS dw.dim_plan_source;
DROP TABLE IF EXISTS dw.dim_sr_group;
GO

CREATE TABLE dw.dim_sr_group (
    sr_group_key         int            NOT NULL CONSTRAINT pk_dw_dim_sr_group PRIMARY KEY,
    sr_group_code        varchar(20)    NOT NULL,
    sr_group_name        nvarchar(200)  NOT NULL,
    member_type          varchar(30)    NOT NULL,   -- spending_review_group | plan_only | combined_pre_2023 | non_department | outturn_only
    is_department_group  bit            NOT NULL,   -- 1 for the 23 groups only
    has_outturn          bit            NOT NULL,   -- 0 where OSCAR has no outturn to compare a plan with; 1 for the groups, the combined group and the outturn-only member
    description          nvarchar(1000) NOT NULL,
    evidence             nvarchar(1000) NOT NULL,
    CONSTRAINT uq_dw_dim_sr_group_code UNIQUE (sr_group_code),
    CONSTRAINT uq_dw_dim_sr_group_name UNIQUE (sr_group_name)
);
GO

INSERT INTO dw.dim_sr_group
    (sr_group_key, sr_group_code, sr_group_name, member_type, is_department_group, has_outturn, description, evidence)
SELECT
    ROW_NUMBER() OVER (
        ORDER BY CASE member_type WHEN 'spending_review_group' THEN 1 WHEN 'plan_only' THEN 2
                                  WHEN 'combined_pre_2023' THEN 3
                                  WHEN 'non_department' THEN 4 ELSE 5 END,
                 sr_group_name),
    sr_group_code, sr_group_name, member_type,
    CAST(CASE WHEN member_type = 'spending_review_group' THEN 1 ELSE 0 END AS bit),
    CAST(CASE WHEN member_type IN ('spending_review_group', 'combined_pre_2023', 'outturn_only') THEN 1 ELSE 0 END AS bit),
    description, evidence
FROM stg.sr_group;
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'Spending Review groups plans are published for, plus plan-only, combined pre-2023, non-department and outturn-only members. Authored list (authored/sr_group.csv); holds no amounts.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'dim_sr_group';
GO
