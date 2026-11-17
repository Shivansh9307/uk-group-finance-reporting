-- scope: full
-- stg.bud_sr_group_by_organisation: the Spending Review group of each organisation, for each BUD vintage
-- and financial year, with the department group it sits in.
--   The key is the organisation, not the department group, because a department group can span two
--   Spending Review groups (CLG085.GROUP covers both "CLG Communities" and "CLG Local Government").
--   Within one workbook an organisation has exactly one Spending Review group and one department group
--   (tested), so (vintage, financial_year, organisation_code) is the key.
--   is_latest_vintage = the vintage is the newest annual release loaded.
-- Reads every row of raw.oscar_bud, Closed ones included (they repeat rows held under another status).

DROP TABLE IF EXISTS stg.bud_sr_group_by_organisation;
GO

CREATE TABLE stg.bud_sr_group_by_organisation (
    vintage                varchar(7)    NOT NULL,
    financial_year         varchar(7)    NOT NULL,
    organisation_code      nvarchar(20)  NOT NULL,
    sr_group_code          nvarchar(20)  NOT NULL,
    sr_group_name          nvarchar(100) NOT NULL,
    department_group_code  nvarchar(20)  NOT NULL,
    is_latest_vintage      bit           NOT NULL,
    CONSTRAINT pk_stg_bud_sr_group_by_organisation PRIMARY KEY (vintage, financial_year, organisation_code)
);
GO

WITH latest AS (
    SELECT MAX(vintage) AS vintage FROM raw.oscar_bud_file WHERE load_status = 'loaded'
)
INSERT INTO stg.bud_sr_group_by_organisation
SELECT r.vintage,
       LEFT(r.year_no, 4) + '-' + RIGHT(r.year_no, 2),
       r.organisation_code,
       MAX(r.sr_group_code),
       MAX(r.sr_group_long_name),
       MAX(r.department_group_code),
       CAST(CASE WHEN r.vintage = (SELECT vintage FROM latest) THEN 1 ELSE 0 END AS bit)
FROM raw.oscar_bud AS r
GROUP BY r.vintage, LEFT(r.year_no, 4) + '-' + RIGHT(r.year_no, 2), r.organisation_code
ORDER BY r.vintage, LEFT(r.year_no, 4) + '-' + RIGHT(r.year_no, 2), r.organisation_code;
GO
