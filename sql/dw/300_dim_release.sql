-- dw.dim_release: one row per in-year release (31 from March 2019 to September 2026).
--   release_key         = release_seq, 1 = March 2019, in publication order
--   label               the release label as the source names it ('2024-06')
--   display_label       short label for a slicer ('Jun 2024')
--   financial_year      the year the release reports on (a June release reports the year that ended in March)
--   first_published     the release date
--   highest_period      the last month it reports: 3, 6, 9 or 12
--   release_in_year     0 for the first release of a financial year, 1, 2, 3 for the later ones
--   is_latest_release   the last release in the data
--   is_year_end_release the release that closes its year, i.e. covers period 12

DROP TABLE IF EXISTS dw.dim_release;
GO

CREATE TABLE dw.dim_release (
    release_key          int           NOT NULL CONSTRAINT pk_dw_dim_release PRIMARY KEY,
    label                varchar(7)    NOT NULL,
    display_label        varchar(20)   NOT NULL,
    release_seq          int           NOT NULL,
    financial_year       varchar(7)    NOT NULL,
    first_published      date          NOT NULL,
    highest_period       tinyint       NOT NULL,
    release_in_year      tinyint       NOT NULL,
    version_label        nvarchar(400) NOT NULL,
    is_latest_release    bit           NOT NULL,
    is_year_end_release  bit           NOT NULL,
    CONSTRAINT uq_dw_dim_release_label UNIQUE (label)
);
GO

INSERT INTO dw.dim_release
    (release_key, label, display_label, release_seq, financial_year, first_published, highest_period,
     release_in_year, version_label, is_latest_release, is_year_end_release)
SELECT r.release_seq, r.release,
       CAST(LEFT(DATENAME(month, DATEFROMPARTS(CAST(LEFT(r.release, 4) AS int), CAST(RIGHT(r.release, 2) AS int), 1)), 3)
            + ' ' + LEFT(r.release, 4) AS varchar(20)),
       r.release_seq, r.financial_year, r.first_published, r.highest_period,
       CAST(ROW_NUMBER() OVER (PARTITION BY r.financial_year ORDER BY r.release_seq) - 1 AS tinyint),
       r.version_label,
       CAST(CASE WHEN r.release_seq = MAX(r.release_seq) OVER () THEN 1 ELSE 0 END AS bit),
       CAST(CASE WHEN r.highest_period = 12 THEN 1 ELSE 0 END AS bit)
FROM stg.release AS r;
GO
