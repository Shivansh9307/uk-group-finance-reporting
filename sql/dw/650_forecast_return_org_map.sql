-- scope: full
-- dw.forecast_return_org_map: which version and durable key of dw.dim_organisation each organisation code of a forecast
-- return belongs to, for each financial year. One row per (financial year, organisation code) found in
-- stg.forecast_return_cell. A code that none of the three methods can place has no row here and its cells go to
-- quarantine.forecast_return_unmapped (sql/dw/652).
--   map_method  'in-year release'  the code is reported in an in-year release of that financial year: the version in force in
--                                  the last such release (dw.organisation_release_map)
--               'code, nearest'    the code is a code of some version of the dimension, but no release of that year reports
--                                  it (every code of FY2017-18, because the first in-year release is March 2019): the version
--                                  of that code whose release range is nearest to the financial year, the earlier on a tie
--               'prefix'           the code is not a code of the dimension; its three-letter prefix is the durable key of a
--                                  body that is (durable_key_rule = 'prefix'), and the nearest version of that key is used
-- The distance between a financial year and a version is 0 if the version's release range overlaps the year's releases,
-- otherwise the number of releases between them; for a year with no release it is the sequence of the version's first
-- release, so the earliest version wins.
-- This file is in the dw layer because it reads dw.dim_organisation and dw.organisation_release_map.

DROP TABLE IF EXISTS dw.forecast_return_org_map;
GO

CREATE TABLE dw.forecast_return_org_map (
    financial_year     varchar(7)    NOT NULL,
    organisation_code  nvarchar(50)  NOT NULL,
    organisation_key   int           NOT NULL,
    durable_key        nvarchar(30)  NOT NULL,
    department_key     int           NOT NULL,
    map_method         varchar(20)   NOT NULL,
    CONSTRAINT pk_dw_forecast_return_org_map PRIMARY KEY (financial_year, organisation_code),
    CONSTRAINT fk_dw_forecast_return_org_map_org FOREIGN KEY (organisation_key) REFERENCES dw.dim_organisation (organisation_key)
);
GO

WITH codes AS (
    SELECT DISTINCT financial_year, organisation_code FROM stg.forecast_return_cell
),
fy_window AS (
    SELECT financial_year, MIN(release_seq) AS lo, MAX(release_seq) AS hi FROM stg.release GROUP BY financial_year
),
in_year AS (
    SELECT c.financial_year, c.organisation_code, m.organisation_key, m.department_key, m.durable_key,
           ROW_NUMBER() OVER (PARTITION BY c.financial_year, c.organisation_code ORDER BY m.release_seq DESC) AS rn
    FROM codes AS c
    JOIN stg.release AS r ON r.financial_year = c.financial_year
    JOIN dw.organisation_release_map AS m ON m.release = r.release AND m.organisation_code = c.organisation_code
),
by_code AS (
    SELECT c.financial_year, c.organisation_code, o.organisation_key, o.department_key, o.durable_key,
           ROW_NUMBER() OVER (PARTITION BY c.financial_year, c.organisation_code
                              ORDER BY d.dist, o.valid_from_release_seq, o.organisation_key) AS rn
    FROM codes AS c
    JOIN dw.dim_organisation AS o ON o.organisation_code = c.organisation_code AND o.organisation_key <> -1
    LEFT JOIN fy_window AS w ON w.financial_year = c.financial_year
    CROSS APPLY (SELECT CASE WHEN w.lo IS NULL THEN o.valid_from_release_seq
                             WHEN o.valid_to_release_seq < w.lo THEN w.lo - o.valid_to_release_seq
                             WHEN o.valid_from_release_seq > w.hi THEN o.valid_from_release_seq - w.hi
                             ELSE 0 END AS dist) AS d
),
by_prefix AS (
    SELECT c.financial_year, c.organisation_code, o.organisation_key, o.department_key, o.durable_key,
           ROW_NUMBER() OVER (PARTITION BY c.financial_year, c.organisation_code
                              ORDER BY d.dist, o.valid_from_release_seq, o.organisation_key) AS rn
    FROM codes AS c
    JOIN dw.dim_organisation AS o ON o.durable_key = LEFT(c.organisation_code, 3) AND o.durable_key_rule = 'prefix'
                                 AND o.organisation_key <> -1
    LEFT JOIN fy_window AS w ON w.financial_year = c.financial_year
    CROSS APPLY (SELECT CASE WHEN w.lo IS NULL THEN o.valid_from_release_seq
                             WHEN o.valid_to_release_seq < w.lo THEN w.lo - o.valid_to_release_seq
                             WHEN o.valid_from_release_seq > w.hi THEN o.valid_from_release_seq - w.hi
                             ELSE 0 END AS dist) AS d
)
INSERT INTO dw.forecast_return_org_map
    (financial_year, organisation_code, organisation_key, durable_key, department_key, map_method)
SELECT c.financial_year, c.organisation_code,
       COALESCE(a.organisation_key, b.organisation_key, p.organisation_key),
       COALESCE(a.durable_key, b.durable_key, p.durable_key),
       COALESCE(a.department_key, b.department_key, p.department_key),
       CASE WHEN a.organisation_key IS NOT NULL THEN 'in-year release'
            WHEN b.organisation_key IS NOT NULL THEN 'code, nearest'
            ELSE 'prefix' END
FROM codes AS c
LEFT JOIN in_year AS a ON a.financial_year = c.financial_year AND a.organisation_code = c.organisation_code AND a.rn = 1
LEFT JOIN by_code AS b ON b.financial_year = c.financial_year AND b.organisation_code = c.organisation_code AND b.rn = 1
LEFT JOIN by_prefix AS p ON p.financial_year = c.financial_year AND p.organisation_code = c.organisation_code AND p.rn = 1
WHERE COALESCE(a.organisation_key, b.organisation_key, p.organisation_key) IS NOT NULL;
GO
