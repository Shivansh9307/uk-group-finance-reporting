-- scope: full
-- stg.bud_organisation_type: organisation code -> organisation type (level 1) -> department group, for each
-- BUD vintage. One row per vintage and combination as it appears (a body can be renamed between vintages).
--   is_latest_vintage = the vintage is the newest annual release loaded.
-- Reads every row of raw.oscar_bud, Closed ones included (they repeat rows held under another status).

DROP TABLE IF EXISTS stg.bud_organisation_type;
GO

CREATE TABLE stg.bud_organisation_type (
    vintage                      varchar(7)    NOT NULL,
    organisation_code            nvarchar(20)  NOT NULL,
    organisation_name            nvarchar(200) NOT NULL,
    organisation_type_code       nvarchar(20)  NOT NULL,
    organisation_type_l1_code    nvarchar(20)  NOT NULL,
    organisation_type_l1_name    nvarchar(100) NOT NULL,
    department_group_code        nvarchar(20)  NOT NULL,
    financial_years              varchar(100)  NOT NULL,
    source_rows                  int           NOT NULL,
    is_latest_vintage            bit           NOT NULL,
    CONSTRAINT pk_stg_bud_organisation_type PRIMARY KEY
        (vintage, organisation_code, organisation_name, organisation_type_code, organisation_type_l1_code,
         organisation_type_l1_name, department_group_code)
);
GO

WITH by_year AS (
    SELECT vintage, organisation_code, organisation_long_name AS organisation_name, organisation_type_code,
           organisation_type_l1_code, organisation_type_l1_long_name AS organisation_type_l1_name,
           department_group_code,
           LEFT(year_no, 4) + '-' + RIGHT(year_no, 2) AS financial_year,
           COUNT_BIG(*) AS source_rows
    FROM raw.oscar_bud
    GROUP BY vintage, organisation_code, organisation_long_name, organisation_type_code, organisation_type_l1_code,
             organisation_type_l1_long_name, department_group_code, LEFT(year_no, 4) + '-' + RIGHT(year_no, 2)
), latest AS (
    SELECT MAX(vintage) AS vintage FROM raw.oscar_bud_file WHERE load_status = 'loaded'
)
INSERT INTO stg.bud_organisation_type
SELECT y.vintage, y.organisation_code, y.organisation_name, y.organisation_type_code, y.organisation_type_l1_code,
       y.organisation_type_l1_name, y.department_group_code,
       STRING_AGG(y.financial_year, ' ') WITHIN GROUP (ORDER BY y.financial_year),
       SUM(y.source_rows),
       CAST(CASE WHEN y.vintage = (SELECT vintage FROM latest) THEN 1 ELSE 0 END AS bit)
FROM by_year AS y
GROUP BY y.vintage, y.organisation_code, y.organisation_name, y.organisation_type_code, y.organisation_type_l1_code,
         y.organisation_type_l1_name, y.department_group_code
ORDER BY y.vintage, y.organisation_code, y.organisation_name, y.department_group_code;
GO
