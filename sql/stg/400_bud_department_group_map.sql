-- scope: full
-- stg.bud_department_group_map: department group -> Spending Review group -> PESA group, for each BUD
-- vintage, read from the rows of that vintage's workbooks (every row, Closed ones included, because
-- they repeat rows held under another status and add no key).
--   One row per vintage and combination of codes and names as they appear. A department group can
--   have more than one Spending Review group (CLG085.GROUP has two), and a name can change between
--   vintages (CLG085.GROUP is DLUHC in 2023-11 and MHCLG later), so the code alone is not a key.
--   is_latest_vintage = the vintage is the newest annual release loaded.
--   financial_years = the years of that vintage in which the combination occurs.

DROP TABLE IF EXISTS stg.bud_department_group_map;
GO

CREATE TABLE stg.bud_department_group_map (
    vintage                      varchar(7)    NOT NULL,
    department_group_code        nvarchar(20)  NOT NULL,
    department_group_name        nvarchar(200) NOT NULL,
    sr_group_code                nvarchar(20)  NOT NULL,
    sr_group_name                nvarchar(100) NOT NULL,
    pesa_group_code              nvarchar(20)  NOT NULL,
    pesa_group_name              nvarchar(100) NOT NULL,
    financial_years              varchar(100)  NOT NULL,   -- e.g. '2020-21 2021-22'
    source_rows                  int           NOT NULL,
    is_latest_vintage            bit           NOT NULL,
    CONSTRAINT pk_stg_bud_department_group_map PRIMARY KEY NONCLUSTERED
        (vintage, department_group_code, department_group_name, sr_group_code, sr_group_name, pesa_group_code, pesa_group_name)
);
GO

WITH by_year AS (
    SELECT vintage,
           department_group_code, department_group_long_name AS department_group_name,
           sr_group_code, sr_group_long_name AS sr_group_name,
           pesa_group_code, pesa_group_long_name AS pesa_group_name,
           LEFT(year_no, 4) + '-' + RIGHT(year_no, 2) AS financial_year,
           COUNT_BIG(*) AS source_rows
    FROM raw.oscar_bud
    GROUP BY vintage, department_group_code, department_group_long_name, sr_group_code, sr_group_long_name,
             pesa_group_code, pesa_group_long_name, LEFT(year_no, 4) + '-' + RIGHT(year_no, 2)
), latest AS (
    SELECT MAX(vintage) AS vintage FROM raw.oscar_bud_file WHERE load_status = 'loaded'
)
INSERT INTO stg.bud_department_group_map
SELECT y.vintage, y.department_group_code, y.department_group_name, y.sr_group_code, y.sr_group_name,
       y.pesa_group_code, y.pesa_group_name,
       STRING_AGG(y.financial_year, ' ') WITHIN GROUP (ORDER BY y.financial_year),
       SUM(y.source_rows),
       CAST(CASE WHEN y.vintage = (SELECT vintage FROM latest) THEN 1 ELSE 0 END AS bit)
FROM by_year AS y
GROUP BY y.vintage, y.department_group_code, y.department_group_name, y.sr_group_code, y.sr_group_name,
         y.pesa_group_code, y.pesa_group_name
ORDER BY y.vintage, y.department_group_code, y.sr_group_code, y.pesa_group_code, y.department_group_name;
GO
