-- phase: pre
-- scope: full
-- Landing tables for the departments' monthly forecast returns (written by ukfr.stages.forecast_returns, stage
-- forecast_returns). They only exist in a full-scope build, because the annual extracts and the MFO zips are not in
-- git. Safe to run again.
--   raw.forecast_return_file      one row per return (an extract member holds fourteen, an MFO csv holds one)
--   raw.forecast_return_cell      the member's data rows added up at the load grain plus the columns that tell one
--                                 kind of row from another (status, type, department group, Spending Review group,
--                                 both control budget names); exact decimal sums, lineage as first and last record
--   raw.forecast_return_expected  the independent recomputation (data/audit/forecast_independent_control.csv)

IF OBJECT_ID(N'raw.forecast_return_file', N'U') IS NULL
CREATE TABLE raw.forecast_return_file (
    file_id           int            NOT NULL,
    family            varchar(10)    NOT NULL,   -- extract | mfo
    source_id         varchar(40)    NOT NULL,
    release           varchar(20)    NOT NULL,
    filename          nvarchar(200)  NOT NULL,   -- the zip
    member            nvarchar(200)  NOT NULL,   -- the txt (extract) or csv (MFO) inside it
    financial_year    varchar(7)     NOT NULL,   -- '2017-18'
    return_no         int            NOT NULL,   -- 0..13
    sha256_manifest   varchar(64)    NOT NULL,
    sha256_file       varchar(64)    NOT NULL,
    source_rows       int            NOT NULL,   -- data records of this return that the load read (all periods)
    repaired_records  int            NOT NULL,   -- records rebuilt from two pieces (one in MFO-R05-2022-23)
    cells             int            NOT NULL,
    CONSTRAINT pk_raw_forecast_return_file PRIMARY KEY (file_id)
);
GO

IF OBJECT_ID(N'raw.forecast_return_cell', N'U') IS NULL
CREATE TABLE raw.forecast_return_cell (
    file_id                 int            NOT NULL,
    cell_id                 int            NOT NULL,
    return_no               int            NOT NULL,
    period                  int            NOT NULL,   -- 0 = budget adjustments (R13 of the extracts), 1..12 = April..March
    status_code             nvarchar(50)   NOT NULL,   -- CONFIRMED | DRAFT (extracts), Confirmed | Locked (MFO), as written
    type_code               nvarchar(50)   NOT NULL,
    department_group_code   nvarchar(50)   NOT NULL,
    department_group_name   nvarchar(400)  NOT NULL,   -- first seen in the cell
    sr_group_code           nvarchar(50)   NOT NULL,
    organisation_code       nvarchar(50)   NOT NULL,
    organisation_name       nvarchar(400)  NOT NULL,   -- first seen in the cell
    economic_category_code  nvarchar(50)   NOT NULL,
    control_budget_l0_name  nvarchar(200)  NOT NULL,
    control_budget_l1_name  nvarchar(200)  NOT NULL,
    economic_budget_code    nvarchar(50)   NOT NULL,
    amount                  decimal(38,16) NOT NULL,   -- exact sum of the source amounts, GBP thousands
    source_rows             int            NOT NULL,
    first_line              int            NOT NULL,   -- data record number inside the member, first data row = 1
    last_line               int            NOT NULL,
    CONSTRAINT pk_raw_forecast_return_cell PRIMARY KEY (cell_id)
);
GO

IF OBJECT_ID(N'raw.forecast_return_expected', N'U') IS NULL
CREATE TABLE raw.forecast_return_expected (
    family          varchar(10)    NOT NULL,
    financial_year  varchar(7)     NOT NULL,
    return_no       int            NOT NULL,
    period          int            NOT NULL,
    data_rows       int            NOT NULL,
    amount_sum      varchar(60)    NOT NULL,   -- exact, as written in the control csv (GBP thousands)
    CONSTRAINT pk_raw_forecast_return_expected PRIMARY KEY (family, financial_year, return_no, period)
);
GO
