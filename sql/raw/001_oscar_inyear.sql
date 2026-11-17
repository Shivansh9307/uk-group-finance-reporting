-- phase: pre
-- Landing tables for the OSCAR II in-year load (written by ukfr.stages.oscar_inyear).
-- Safe to run again: each table is created only if it is missing.

IF OBJECT_ID(N'raw.oscar_inyear_file', N'U') IS NULL
CREATE TABLE raw.oscar_inyear_file (
    file_id               int           NOT NULL CONSTRAINT pk_raw_oscar_inyear_file PRIMARY KEY,
    release               varchar(7)    NOT NULL,
    filename              nvarchar(260) NOT NULL,
    member                nvarchar(260) NOT NULL,   -- zip member holding the data, '' for a bare file
    container             varchar(10)   NOT NULL,   -- zip-csv, zip-ods, csv or ods
    primary_for_release   char(1)       NOT NULL,   -- Y = the file that is loaded
    first_published       varchar(40)   NOT NULL,   -- as written in data/manifest/files.csv
    sha256_manifest       char(64)      NOT NULL,   -- from data/manifest/files.csv
    sha256_file           char(64)      NOT NULL,   -- hashed again by the loader
    header_variant        varchar(20)   NOT NULL,
    sheet                 nvarchar(260) NOT NULL,
    total_rows            int           NOT NULL,   -- every row after the header, blank ones included
    blank_rows            int           NOT NULL,
    data_rows             int           NOT NULL,   -- rows read: loaded + quarantined for a primary file
    load_status           varchar(30)   NOT NULL,   -- loaded | duplicate_of_primary
    duplicate_of_file_id  int           NULL,
    duplicate_identical   bit           NULL,       -- same multiset of rows and exact amounts as the primary
    content_digest        char(64)      NULL        -- order-independent digest, kept for files with a twin
);
GO

IF OBJECT_ID(N'raw.oscar_inyear', N'U') IS NULL
BEGIN
    CREATE TABLE raw.oscar_inyear (
        file_id                      int           NOT NULL,
        source_row                   int           NOT NULL,   -- row number in the source (header = 1, blank rows counted)
        release                      varchar(7)    NOT NULL,
        organisation_code            nvarchar(50)  NOT NULL,
        organisation_name            nvarchar(400) NOT NULL,
        control_budget_code          nvarchar(100) NOT NULL,
        control_budget_detail_code   nvarchar(100) NOT NULL,
        department_name              nvarchar(400) NOT NULL,
        sub_segment_code             nvarchar(50)  NOT NULL,
        sub_segment_name             nvarchar(1000) NOT NULL,
        economic_category_code       nvarchar(50)  NOT NULL,
        economic_category_name       nvarchar(400) NOT NULL,
        economic_budget_code         nvarchar(100) NOT NULL,
        pesa_economic_group_code     nvarchar(400) NOT NULL,
        pesa_economic_group_name     nvarchar(400) NOT NULL,   -- '' outside the 2019 layout
        version                      nvarchar(400) NOT NULL,
        [year]                       nvarchar(100) NOT NULL,
        quarter                      nvarchar(100) NOT NULL,
        [month]                      nvarchar(100) NOT NULL,
        amount_text                  nvarchar(100) NOT NULL,   -- as read, GBP thousands
        amount_whole                 bigint        NOT NULL,   -- integer part of the exact amount
        amount_frac                  decimal(38,31) NOT NULL   -- the rest; amount = whole + frac, same sign
    );
    CREATE CLUSTERED COLUMNSTORE INDEX cci_raw_oscar_inyear ON raw.oscar_inyear;
END;
GO

IF OBJECT_ID(N'raw.oscar_inyear_control_expected', N'U') IS NULL
CREATE TABLE raw.oscar_inyear_control_expected (
    release                 varchar(7)    NOT NULL,
    filename                nvarchar(260) NOT NULL,
    primary_for_release     char(1)       NOT NULL,
    sha256                  char(64)      NOT NULL,
    total_rows              int           NOT NULL,
    blank_rows              int           NOT NULL,
    data_rows               int           NOT NULL,
    zero_rows               int           NOT NULL,
    amount_sum              varchar(100)  NOT NULL,   -- exact, plain text
    amount_sum_rounded_4dp  varchar(100)  NOT NULL,
    CONSTRAINT pk_raw_oscar_inyear_control_expected PRIMARY KEY (release, filename)
);
GO
