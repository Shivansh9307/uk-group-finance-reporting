-- phase: pre
-- scope: full
-- Landing tables for the departmental workforce management information files (written by ukfr.stages.workforce).
-- The files are under $UKFR_DATA_DIR (not in git), so this file runs only in a full build.
-- Nothing is typed beyond what the file says: the organisation name is as published, a number keeps the text it was
-- read from, a blank cell has no row (blank is not zero).

IF OBJECT_ID(N'raw.workforce_file', N'U') IS NULL
CREATE TABLE raw.workforce_file (
    file_id          int           NOT NULL CONSTRAINT pk_raw_workforce_file PRIMARY KEY,
    dept             varchar(20)   NOT NULL,   -- the collection, from the release label (dft, defra, mod ...)
    report_month     char(7)       NOT NULL,   -- 2024-05, the month the file is published for
    release          varchar(40)   NOT NULL,   -- dft-2024-05
    filename         nvarchar(260) NOT NULL,
    path             nvarchar(400) NOT NULL,   -- as in data/manifest/files.csv ($UKFR_DATA_DIR/...)
    format           varchar(5)    NOT NULL,   -- csv | xlsx | xls | ods
    is_primary       bit           NOT NULL,   -- 1: the copy the warehouse uses; 0: the same month in another format (cross-check only)
    load_status      varchar(10)   NOT NULL,   -- loaded | skipped
    skip_reason      nvarchar(400) NOT NULL,   -- from data/manifest/workforce_skipped_files.csv; empty when loaded
    sha256_manifest  char(64)      NOT NULL,
    sha256_file      varchar(64)   NOT NULL,
    sheet            nvarchar(100) NOT NULL,
    template         varchar(20)   NOT NULL,   -- single_row | multi_row (how many header rows the file has)
    header_line      int           NOT NULL,   -- 1-based row of the first header row
    header_rows      int           NOT NULL,
    total_rows       int           NOT NULL,   -- rows after the header block
    blank_rows       int           NOT NULL,
    data_rows        int           NOT NULL,
    n_columns        int           NOT NULL    -- columns the reader recognised
);
GO

IF OBJECT_ID(N'raw.workforce_row', N'U') IS NULL
CREATE TABLE raw.workforce_row (
    file_id             int            NOT NULL,
    source_row          int            NOT NULL,   -- 1-based row in the sheet
    year_text           varchar(20)    NOT NULL,
    month_text          varchar(40)    NOT NULL,
    organisation_name   nvarchar(400)  NOT NULL,   -- as published (white space collapsed)
    organisation_type   nvarchar(200)  NOT NULL,
    parent_department   nvarchar(400)  NOT NULL,
    CONSTRAINT pk_raw_workforce_row PRIMARY KEY (file_id, source_row)
);
GO

IF OBJECT_ID(N'raw.workforce_value', N'U') IS NULL
CREATE TABLE raw.workforce_value (
    file_id        int            NOT NULL,
    source_row     int            NOT NULL,
    column_index   int            NOT NULL,   -- 0-based column in the sheet
    measure_key    varchar(60)    NOT NULL,   -- what the reader decided the column is (readers/workforce.py)
    column_label   nvarchar(400)  NOT NULL,   -- the header as published
    value_text     nvarchar(100)  NOT NULL,
    value          decimal(38,10) NOT NULL,   -- headcount and full-time equivalent as published; paybill in pounds
    CONSTRAINT pk_raw_workforce_value PRIMARY KEY (file_id, source_row, column_index)
);
GO

IF OBJECT_ID(N'raw.workforce_ignored_column', N'U') IS NULL
CREATE TABLE raw.workforce_ignored_column (
    file_id       int            NOT NULL,
    column_index  int            NOT NULL,
    column_label  nvarchar(400)  NOT NULL,   -- a comment or note column; not read
    CONSTRAINT pk_raw_workforce_ignored_column PRIMARY KEY (file_id, column_index)
);
GO

IF OBJECT_ID(N'raw.workforce_control_expected', N'U') IS NULL
CREATE TABLE raw.workforce_control_expected (
    dept              varchar(20)    NOT NULL,
    report_month      char(7)        NOT NULL,
    filename          nvarchar(260)  NOT NULL,
    sheet             nvarchar(100)  NOT NULL,
    column_index      int            NOT NULL,
    data_rows         int            NOT NULL,   -- rows of the file whose first cell is a four-digit year
    numeric_cells     int            NOT NULL,
    nonnumeric_cells  int            NOT NULL,
    value_sum         decimal(38,10) NOT NULL,
    CONSTRAINT pk_raw_workforce_control_expected PRIMARY KEY (dept, report_month, filename, column_index)
);
GO
