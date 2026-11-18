-- dw.outturn_sr_group_bridge: the Spending Review group of every (organisation version, sub-segment) pair
-- in the outturn, so that outturn can be set beside the plans, which are published by group.
--   Grain: organisation_key x sub_segment_code, the same pairs as stg.current_structure_map (one row each).
--   The group follows the line's CURRENT department (stg.current_structure_map.current_department_key; the
--   view is read, its rule is not copied here), because the groups are the current structure. The department
--   number then picks the group from authored/department_sr_group.csv:
--     organisation exception  the durable key of the organisation has its own row for that department number
--                             (department 085 feeds CLG Communities and CLG Local Government; the split is by
--                             organisation, never by weight)
--     department              the department number's own row
--     unallocated member      the current department is an Unallocated member of dim_department (lines of a closed
--                             or split department with no current home: U084, U011, U077, U035): it goes to the
--                             non-department member 'Unallocated central funds'
--     unknown department      the structure map has no department for the pair: the same non-department member.
--                             A test fails if any pair lands here, so it cannot hide a real department.
--   A department of member type Department that has no row in the file stops the build.
--   No weights and no estimates: a pair has one group or the build fails.
-- Authored mapping applied to real keys; it holds no amount.

DROP TABLE IF EXISTS dw.outturn_sr_group_bridge;
GO

DECLARE @missing nvarchar(2000) = (
    SELECT STRING_AGG(x.department_number, ', ') WITHIN GROUP (ORDER BY x.department_number)
    FROM (SELECT DISTINCT d.department_number
          FROM stg.current_structure_map AS m
          JOIN dw.dim_department AS d ON d.department_key = m.current_department_key
          WHERE d.member_type = 'Department'
            AND NOT EXISTS (SELECT 1 FROM stg.department_sr_group AS r
                            WHERE r.department_number = d.department_number AND r.durable_key = '' AND r.basis = 'current')) AS x);
IF @missing IS NOT NULL
BEGIN
    DECLARE @msg nvarchar(2100) = N'authored/department_sr_group.csv has no current row for department number(s): ' + @missing;
    THROW 50560, @msg, 1;
END
GO

CREATE TABLE dw.outturn_sr_group_bridge (
    organisation_key        int           NOT NULL,
    sub_segment_code        nvarchar(50)  NOT NULL,
    current_department_key  int           NOT NULL,
    department_number       nvarchar(10)  NOT NULL,
    durable_key             nvarchar(30)  NOT NULL,
    sr_group_key            int           NOT NULL,
    bridge_rule             varchar(30)   NOT NULL,   -- organisation exception | department | unallocated member | unknown department
    CONSTRAINT pk_dw_outturn_sr_group_bridge PRIMARY KEY (organisation_key, sub_segment_code),
    CONSTRAINT fk_dw_outturn_sr_group_bridge_group FOREIGN KEY (sr_group_key) REFERENCES dw.dim_sr_group (sr_group_key)
);
GO

INSERT INTO dw.outturn_sr_group_bridge
    (organisation_key, sub_segment_code, current_department_key, department_number, durable_key, sr_group_key, bridge_rule)
SELECT m.organisation_key, m.sub_segment_code, m.current_department_key, d.department_number, o.durable_key,
       COALESCE(gx.sr_group_key, gd.sr_group_key, gu.sr_group_key),
       CAST(CASE WHEN gx.sr_group_key IS NOT NULL THEN 'organisation exception'
                 WHEN gd.sr_group_key IS NOT NULL THEN 'department'
                 WHEN d.member_type = 'Unallocated' THEN 'unallocated member'
                 ELSE 'unknown department' END AS varchar(30))
FROM stg.current_structure_map AS m
JOIN dw.dim_organisation AS o ON o.organisation_key = m.organisation_key
JOIN dw.dim_department AS d ON d.department_key = m.current_department_key
LEFT JOIN stg.department_sr_group AS rx
       ON rx.department_number = d.department_number AND rx.durable_key = o.durable_key AND rx.basis = 'current'
LEFT JOIN dw.dim_sr_group AS gx ON gx.sr_group_code = rx.sr_group_code
LEFT JOIN stg.department_sr_group AS rd
       ON rd.department_number = d.department_number AND rd.durable_key = '' AND rd.basis = 'current'
LEFT JOIN dw.dim_sr_group AS gd ON gd.sr_group_code = rd.sr_group_code
CROSS JOIN (SELECT sr_group_key FROM dw.dim_sr_group WHERE sr_group_code = 'NONDEPT_UNALLOC') AS gu;
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'The Spending Review group of each organisation version and sub-segment pair in the outturn, by the current department and authored/department_sr_group.csv. A mapping, not a total: it holds no amount. Real keys, authored rule.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'outturn_sr_group_bridge';
GO
