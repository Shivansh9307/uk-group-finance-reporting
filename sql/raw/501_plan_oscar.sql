-- phase: pre
-- scope: full
-- Landing tables for the OSCAR Plans (written by ukfr.stages.plans, stage plans_oscar). They only exist in a
-- full-scope build, because the extracts are not in git. Safe to run again.
--   raw.plan_oscar           the PLANS rows of the OSCAR annual extracts
--   raw.plan_oscar_expected  control figures for the OSCAR plan rows (from csv files that are in git)

IF OBJECT_ID(N'raw.plan_oscar', N'U') IS NULL
CREATE TABLE raw.plan_oscar (
    file_id                     int            NOT NULL,
    source_row                  int            NOT NULL,   -- data row in the extract, first data row = 1
    year_short_name             varchar(7)     NOT NULL,
    month_short_name            nvarchar(30)   NOT NULL,   -- 'Period 0 - 21-22' on every plan row
    department_group_code       nvarchar(50)   NOT NULL,
    department_group_name       nvarchar(400)  NOT NULL,
    sr_group_code               nvarchar(50)   NOT NULL,
    sr_group_name               nvarchar(400)  NOT NULL,
    organisation_code           nvarchar(50)   NOT NULL,
    organisation_name           nvarchar(400)  NOT NULL,
    segment_l4_code             nvarchar(50)   NOT NULL,
    control_budget_l0_name      nvarchar(200)  NOT NULL,
    control_budget_l1_name      nvarchar(200)  NOT NULL,
    economic_budget_code        nvarchar(50)   NOT NULL,
    economic_ringfence_code     nvarchar(100)  NOT NULL,
    economic_group_code         nvarchar(50)   NOT NULL,
    economic_category_code      nvarchar(50)   NOT NULL,
    usage_code                  nvarchar(50)   NOT NULL,
    status_code                 nvarchar(50)   NOT NULL,
    type_code                   nvarchar(50)   NOT NULL,
    version_code                nvarchar(50)   NOT NULL,
    amount_text                 varchar(40)    NOT NULL,   -- as written: ' 000000000005000.' (GBP thousands)
    CONSTRAINT pk_raw_plan_oscar PRIMARY KEY (file_id, source_row)
);
GO

IF OBJECT_ID(N'raw.plan_oscar_expected', N'U') IS NULL
CREATE TABLE raw.plan_oscar_expected (
    control                varchar(30)   NOT NULL,   -- file_plans_rows | group_totals
    fiscal_year            varchar(7)    NOT NULL,
    department_group_code  nvarchar(50)  NOT NULL,   -- '' for file_plans_rows
    control_budget_detail  nvarchar(50)  NOT NULL,   -- '' for file_plans_rows
    economic_budget        nvarchar(50)  NOT NULL,   -- '' for file_plans_rows
    plans_rows             int           NOT NULL,
    plans_gbp_thousand     varchar(40)   NULL,       -- as written in the control csv; NULL for file_plans_rows
    CONSTRAINT pk_raw_plan_oscar_expected PRIMARY KEY
        (control, fiscal_year, department_group_code, control_budget_detail, economic_budget)
);
GO
