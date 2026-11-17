-- phase: pre
-- Landing tables for the plan sources (written by ukfr.stages.plans). Safe to run again.
--   raw.plan_source_file     one row per workbook or extract zip that was read
--   raw.plan_estimates       every cell of every table sheet of the Estimates "Departmental DEL budgets" workbooks
--   raw.plan_pesa            the same for the PESA Chapter 1 workbooks and the Spending Review 2025 DEL tables
-- Values are kept as published: the unit text, the row label with its footnote marker, the year label and
-- the status label above or below the year. Nothing is converted to GBP thousands here.

IF OBJECT_ID(N'raw.plan_source_file', N'U') IS NULL
CREATE TABLE raw.plan_source_file (
    file_id           int           NOT NULL CONSTRAINT pk_raw_plan_source_file PRIMARY KEY,
    family            varchar(20)   NOT NULL,   -- estimates | pesa | oscar_extract
    source_id         varchar(30)   NOT NULL,   -- as in data/manifest/files.csv
    release           varchar(30)   NOT NULL,   -- manifest release (2023-24-supps, 2025, sr2025, 2022-11)
    edition           varchar(30)   NOT NULL,   -- label used in the plan source dimension (2025-12 for the December PESA update)
    filename          nvarchar(260) NOT NULL,
    sha256_manifest   char(64)      NOT NULL,
    sha256_file       char(64)      NOT NULL,   -- hashed again at load
    first_published   varchar(40)   NOT NULL,   -- as written in the manifest
    sheets_read       int           NOT NULL,
    rows_loaded       int           NOT NULL
);
GO

IF OBJECT_ID(N'raw.plan_estimates', N'U') IS NULL
CREATE TABLE raw.plan_estimates (
    file_id          int            NOT NULL,
    source_row       int            NOT NULL,   -- row in the sheet, 1-based
    sheet            nvarchar(100)  NOT NULL,
    table_title      nvarchar(400)  NOT NULL,   -- first text cell of the sheet; the measure is read from this
    unit             nvarchar(100)  NOT NULL,   -- as written ('<pound> billion'; the pound sign is U+FFFD in some workbooks)
    section          nvarchar(400)  NOT NULL,   -- last heading above the row, '' if none
    row_label        nvarchar(400)  NOT NULL,   -- as written, with the footnote marker
    row_label_clean  nvarchar(400)  NOT NULL,   -- footnote markers and stray spaces removed
    row_kind         varchar(10)    NOT NULL,   -- line | total | memo, as the reader classified it
    year_label       varchar(7)     NOT NULL,   -- 2023-24
    status_label     varchar(20)    NOT NULL,   -- plans | outturn | '' as written above or below the year
    value_text       varchar(60)    NULL,       -- the number as read (15 significant digits), NULL for '-' or blank
    value_published  decimal(38,18) NULL,       -- the same, in the unit of the sheet
    CONSTRAINT pk_raw_plan_estimates PRIMARY KEY (file_id, sheet, source_row, year_label)
);
GO

IF OBJECT_ID(N'raw.plan_pesa', N'U') IS NULL
CREATE TABLE raw.plan_pesa (
    file_id          int            NOT NULL,
    source_row       int            NOT NULL,
    sheet            nvarchar(100)  NOT NULL,
    table_title      nvarchar(400)  NOT NULL,
    unit             nvarchar(100)  NOT NULL,
    section          nvarchar(400)  NOT NULL,
    row_label        nvarchar(400)  NOT NULL,
    row_label_clean  nvarchar(400)  NOT NULL,
    row_kind         varchar(10)    NOT NULL,
    year_label       varchar(7)     NOT NULL,
    status_label     varchar(20)    NOT NULL,
    value_text       varchar(60)    NULL,
    value_published  decimal(38,18) NULL,
    CONSTRAINT pk_raw_plan_pesa PRIMARY KEY (file_id, sheet, source_row, year_label)
);
GO
