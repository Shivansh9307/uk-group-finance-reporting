-- phase: pre
-- scope: full
-- Landing tables for the Public Spending Statistics database (written by ukfr.stages.pss).
-- The workbook is not in git (it sits under $UKFR_DATA_DIR), so this file runs only in a full build.

IF OBJECT_ID(N'raw.pss_file', N'U') IS NULL
CREATE TABLE raw.pss_file (
    file_id          int           NOT NULL CONSTRAINT pk_raw_pss_file PRIMARY KEY,
    release          varchar(7)    NOT NULL,   -- 2026-07
    filename         nvarchar(260) NOT NULL,
    path             nvarchar(400) NOT NULL,   -- as in data/manifest/files.csv ($UKFR_DATA_DIR/...)
    file_kind        varchar(10)   NOT NULL,   -- database | tables
    load_status      varchar(10)   NOT NULL,   -- loaded | skipped
    skip_reason      nvarchar(200) NOT NULL,
    sha256_manifest  char(64)      NOT NULL,
    sha256_file      varchar(64)   NOT NULL,
    sheets           nvarchar(400) NOT NULL,
    total_rows       int           NOT NULL,
    blank_rows       int           NOT NULL,
    data_rows        int           NOT NULL
);
GO

IF OBJECT_ID(N'raw.pss', N'U') IS NULL
BEGIN
    CREATE TABLE raw.pss (
        file_id                        int            NOT NULL,
        source_row                     int            NOT NULL,   -- row number in the Database sheet (header = 1)
        [year]                         nvarchar(20)   NOT NULL,   -- '2023-24'
        economic_budget_code           nvarchar(50)   NOT NULL,
        economic_ringfence_code        nvarchar(100)  NOT NULL,
        control_budget_code            nvarchar(50)   NOT NULL,
        control_budget_detail_code     nvarchar(50)   NOT NULL,
        sr_group_long_name             nvarchar(200)  NOT NULL,
        segment_code                   nvarchar(50)   NOT NULL,
        segment_long_name              nvarchar(1000) NOT NULL,
        pesa_economic_group_long_name  nvarchar(400)  NOT NULL,
        amount_text                    nvarchar(100)  NOT NULL,   -- GBP thousands as read
        amount                         decimal(38,10) NOT NULL
    );
    CREATE CLUSTERED COLUMNSTORE INDEX cci_raw_pss ON raw.pss;
END;
GO

IF OBJECT_ID(N'raw.pss_control_expected', N'U') IS NULL
CREATE TABLE raw.pss_control_expected (
    filename        nvarchar(260)  NOT NULL,
    sheet           nvarchar(100)  NOT NULL,
    n_columns       int            NOT NULL,
    total_rows      int            NOT NULL,   -- rows in the whole sheet, repeated on every year line
    financial_year  varchar(7)     NOT NULL,
    amount_total    decimal(38,10) NOT NULL,   -- GBP thousands
    CONSTRAINT pk_raw_pss_control_expected PRIMARY KEY (filename, financial_year)
);
GO

IF OBJECT_ID(N'raw.pss_independent_expected', N'U') IS NULL
CREATE TABLE raw.pss_independent_expected (
    filename        nvarchar(260)  NOT NULL,
    sheet           nvarchar(100)  NOT NULL,
    financial_year  varchar(7)     NOT NULL,
    data_rows       int            NOT NULL,
    amount_sum      decimal(38,10) NOT NULL,
    CONSTRAINT pk_raw_pss_independent_expected PRIMARY KEY (filename, financial_year)
);
GO
