-- scope: full
-- dw.tac_provider_year and dw.tac_provider: the NHS trusts and foundation trusts of the TAC files.
--   dw.tac_provider_year   one row per provider and year it is listed: the name, type, sector and region of that
--                          year, whether the file has its statements, and why not when it has none (list_status)
--   dw.tac_provider        one row per NHS code. Name, type, region and sector are the latest listed year's.
--                          first/last_data_release span the years with statements; n_data_years counts them
--                          (a provider can be missing in the middle: see list_status).
--                          successor_*: where the body went when it was acquired, merged or dissolved, from
--                          authored/tac_provider_successor.csv (authored; the evidence is a quotation from the
--                          source's own comment, and a test finds it in the raw comments). successor_provider_key
--                          is NULL when the successor is not a TAC provider (an integrated care board).
-- The group link to the Department of Health and Social Care is in dw.tac_provider_group (sql/audit/102),
-- because the department dimension is built after this file.
-- Objects that point at these tables are dropped first, so a rebuild into an existing database works.

DROP TABLE IF EXISTS dw.tac_provider_group;
GO
DROP TABLE IF EXISTS dw.tac_fact;
GO
DROP TABLE IF EXISTS dw.tac_provider_year;
GO
DROP TABLE IF EXISTS dw.tac_provider;
GO

CREATE TABLE dw.tac_provider (
    provider_key           int            NOT NULL CONSTRAINT pk_dw_tac_provider PRIMARY KEY,
    provider_code          nvarchar(20)   NOT NULL CONSTRAINT uq_dw_tac_provider_code UNIQUE,
    provider_name          nvarchar(300)  NOT NULL,
    provider_type          varchar(30)    NOT NULL,
    region                 nvarchar(100)  NOT NULL,
    sector                 nvarchar(100)  NOT NULL,
    first_listed_release   varchar(7)     NOT NULL,
    last_listed_release    varchar(7)     NOT NULL,
    first_data_release     varchar(7)     NULL,
    last_data_release      varchar(7)     NULL,
    n_data_years           int            NOT NULL,
    successor_code         nvarchar(20)   NULL,
    successor_provider_key int            NULL,
    successor_kind         varchar(20)    NULL,
    successor_effective_date date         NULL
);
GO

CREATE TABLE dw.tac_provider_year (
    provider_key        int            NOT NULL,
    release             varchar(7)     NOT NULL,
    provider_type       varchar(30)    NOT NULL,
    provider_name       nvarchar(300)  NOT NULL,
    region              nvarchar(100)  NOT NULL,
    sector              nvarchar(100)  NOT NULL,
    authorisation_date  nvarchar(40)   NOT NULL,
    has_statement_data  bit            NOT NULL,
    list_status         varchar(25)    NOT NULL,
    source_comment      nvarchar(2000) NOT NULL,
    file_id             int            NOT NULL,
    source_row          int            NOT NULL,
    CONSTRAINT pk_dw_tac_provider_year PRIMARY KEY (provider_key, release),
    CONSTRAINT fk_dw_tac_provider_year_provider FOREIGN KEY (provider_key) REFERENCES dw.tac_provider (provider_key)
);
GO

INSERT INTO dw.tac_provider
    (provider_key, provider_code, provider_name, provider_type, region, sector, first_listed_release,
     last_listed_release, first_data_release, last_data_release, n_data_years)
SELECT ROW_NUMBER() OVER (ORDER BY c.provider_code), c.provider_code, latest.provider_name, latest.provider_type,
       latest.region, latest.sector, c.first_listed, c.last_listed, c.first_data, c.last_data, c.n_data
FROM (SELECT provider_code, MIN(release) AS first_listed, MAX(release) AS last_listed,
             MIN(CASE WHEN has_statement_data = 1 THEN release END) AS first_data,
             MAX(CASE WHEN has_statement_data = 1 THEN release END) AS last_data,
             SUM(CASE WHEN has_statement_data = 1 THEN 1 ELSE 0 END) AS n_data
      FROM stg.tac_provider_year GROUP BY provider_code) AS c
CROSS APPLY (SELECT TOP (1) y.provider_name, y.provider_type, y.region, y.sector
             FROM stg.tac_provider_year AS y
             WHERE y.provider_code = c.provider_code
             ORDER BY y.release DESC) AS latest;
GO

INSERT INTO dw.tac_provider_year
    (provider_key, release, provider_type, provider_name, region, sector, authorisation_date, has_statement_data,
     list_status, source_comment, file_id, source_row)
SELECT p.provider_key, y.release, y.provider_type, y.provider_name, y.region, y.sector, y.authorisation_date,
       y.has_statement_data, y.list_status, y.comment_text, y.file_id, y.source_row
FROM stg.tac_provider_year AS y
JOIN dw.tac_provider AS p ON p.provider_code = y.provider_code;
GO

UPDATE p
SET successor_code = s.successor_code,
    successor_provider_key = sp.provider_key,
    successor_kind = s.change_kind,
    successor_effective_date = s.effective_date
FROM dw.tac_provider AS p
JOIN stg.tac_provider_successor AS s ON s.predecessor_code = p.provider_code
LEFT JOIN dw.tac_provider AS sp ON sp.provider_code = s.successor_code;
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'NHS trusts and foundation trusts in the TAC files, one row per NHS (ODS) code. Real data from the List of providers sheets; the successor columns come from authored/tac_provider_successor.csv (authored, quoted from the source comments).',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'tac_provider';
GO
