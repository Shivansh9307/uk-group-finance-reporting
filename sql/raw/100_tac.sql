-- phase: pre
-- scope: full
-- Landing tables for the NHS trust accounts consolidation (TAC) files (written by ukfr.stages.tac).
-- The workbooks are not in git (they sit under $UKFR_DATA_DIR), so this file runs only in a full build.
-- Everything is text as read, plus the value as an exact decimal. TAC amounts are thousands of pounds.

IF OBJECT_ID(N'raw.tac_file', N'U') IS NULL
CREATE TABLE raw.tac_file (
    file_id          int            NOT NULL CONSTRAINT pk_raw_tac_file PRIMARY KEY,
    release          varchar(7)     NOT NULL,   -- financial year of the accounts, 2024-25
    filename         nvarchar(260)  NOT NULL,
    path             nvarchar(400)  NOT NULL,   -- as in data/manifest/files.csv ($UKFR_DATA_DIR/...)
    file_kind        varchar(10)    NOT NULL,   -- data | template (the illustrative form with no data)
    provider_type    varchar(30)    NOT NULL,   -- NHS trust | NHS foundation trust; empty for a template
    sha256_manifest  char(64)       NOT NULL,
    sha256_file      varchar(64)    NOT NULL,
    sheets           nvarchar(1000) NOT NULL,
    data_header      nvarchar(400)  NOT NULL,   -- the header row of `All data` as written, joined with |
    total_rows       int            NOT NULL,   -- rows after the header in `All data`
    blank_rows       int            NOT NULL,
    data_rows        int            NOT NULL,   -- non-blank rows in `All data`, every worksheet
    statement_rows   int            NOT NULL    -- the rows of the three statements, loaded into raw.tac_value
);
GO

IF OBJECT_ID(N'raw.tac_worksheet', N'U') IS NULL
CREATE TABLE raw.tac_worksheet (
    file_id         int          NOT NULL,
    worksheet_name  nvarchar(60) NOT NULL,
    data_rows       int          NOT NULL,   -- rows of this worksheet in `All data`
    loaded          bit          NOT NULL,   -- 1 for the three statements, 0 for the notes
    CONSTRAINT pk_raw_tac_worksheet PRIMARY KEY (file_id, worksheet_name)
);
GO

IF OBJECT_ID(N'raw.tac_value', N'U') IS NULL
BEGIN
    CREATE TABLE raw.tac_value (
        file_id            int            NOT NULL,
        source_row         int            NOT NULL,   -- row number in `All data` (header = 1)
        organisation_name  nvarchar(300)  NOT NULL,   -- as written, including damaged apostrophes
        worksheet_name     nvarchar(60)   NOT NULL,   -- TAC02 SoCI | TAC03 SoFP | TAC05 SoCF
        table_id           varchar(10)    NOT NULL,
        main_code          varchar(20)    NOT NULL,   -- A03CY01: sheet 03, current year, column 01
        row_number         varchar(10)    NOT NULL,   -- row in the TAC form
        sub_code           varchar(20)    NOT NULL,   -- the line, SCI0100A
        value_text         nvarchar(60)   NOT NULL,   -- thousands of pounds, as read
        value              decimal(38,10) NOT NULL
    );
    CREATE CLUSTERED COLUMNSTORE INDEX cci_raw_tac_value ON raw.tac_value;
END;
GO

IF OBJECT_ID(N'raw.tac_provider_list', N'U') IS NULL
CREATE TABLE raw.tac_provider_list (
    file_id            int            NOT NULL,
    source_row         int            NOT NULL,   -- row in `List of providers` (header = 1)
    provider_name      nvarchar(300)  NOT NULL,
    nhs_code           nvarchar(20)   NOT NULL,
    authorisation_date nvarchar(40)   NOT NULL,   -- foundation trusts only, as written
    region             nvarchar(100)  NOT NULL,
    sector             nvarchar(100)  NOT NULL,
    comments           nvarchar(2000) NOT NULL,
    CONSTRAINT pk_raw_tac_provider_list PRIMARY KEY (file_id, source_row)
);
GO

IF OBJECT_ID(N'raw.tac_intro', N'U') IS NULL
CREATE TABLE raw.tac_intro (
    file_id     int            NOT NULL,
    source_row  int            NOT NULL,
    intro_text  nvarchar(max)  NOT NULL,
    CONSTRAINT pk_raw_tac_intro PRIMARY KEY (file_id, source_row)
);
GO

IF OBJECT_ID(N'raw.tac_template_line', N'U') IS NULL
CREATE TABLE raw.tac_template_line (
    file_id        int            NOT NULL,
    worksheet_name nvarchar(60)   NOT NULL,
    source_row     int            NOT NULL,
    table_id       varchar(10)    NOT NULL,
    label          nvarchar(400)  NOT NULL,   -- the line text printed in the form (a heading when sub_code is empty)
    expected_sign  varchar(5)     NOT NULL,   -- +, -, +/- or empty
    sub_code       varchar(20)    NOT NULL,
    main_code_cy   varchar(20)    NOT NULL,
    main_code_py   varchar(20)    NOT NULL,
    CONSTRAINT pk_raw_tac_template_line PRIMARY KEY (file_id, worksheet_name, source_row)
);
GO

-- The independent control (data/audit/tac_independent_control.csv), landed as written.
IF OBJECT_ID(N'raw.tac_independent_expected', N'U') IS NULL
CREATE TABLE raw.tac_independent_expected (
    release         varchar(7)     NOT NULL,
    filename        nvarchar(260)  NOT NULL,
    worksheet_name  nvarchar(60)   NOT NULL,
    data_rows       int            NOT NULL,   -- rows of this worksheet in `All data`
    value_sum       decimal(38,10) NOT NULL,   -- exact sum of the value column, thousands of pounds
    CONSTRAINT pk_raw_tac_independent_expected PRIMARY KEY (filename, worksheet_name)
);
GO
