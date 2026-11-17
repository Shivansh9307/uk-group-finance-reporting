-- phase: pre
-- scope: full
-- Landing tables for the OSCAR annual restated ("BUD") workbooks (written by ukfr.stages.oscar_bud).
-- The workbooks are not in git (they sit under $UKFR_DATA_DIR), so this file runs only in a full build.
-- Safe to run again: each table is created only if it is missing.

IF OBJECT_ID(N'raw.oscar_bud_file', N'U') IS NULL
CREATE TABLE raw.oscar_bud_file (
    file_id          int           NOT NULL CONSTRAINT pk_raw_oscar_bud_file PRIMARY KEY,
    vintage          varchar(7)    NOT NULL,   -- annual release: 2023-11, 2024-11, 2025-11
    filename         nvarchar(260) NOT NULL,
    path             nvarchar(400) NOT NULL,   -- as in data/manifest/files.csv ($UKFR_DATA_DIR/...)
    file_kind        varchar(10)   NOT NULL,   -- data | guidance
    load_status      varchar(10)   NOT NULL,   -- loaded | skipped
    skip_reason      nvarchar(200) NOT NULL,   -- why a file is skipped, '' for a loaded one
    sha256_manifest  char(64)      NOT NULL,
    sha256_file      varchar(64)   NOT NULL,   -- hashed again by the loader, '' if the file is absent
    financial_year   varchar(7)    NOT NULL,   -- '' for a skipped file
    sheet            nvarchar(260) NOT NULL,
    other_sheets     nvarchar(400) NOT NULL,   -- empty sheets in the workbook
    total_rows       int           NOT NULL,
    blank_rows       int           NOT NULL,
    data_rows        int           NOT NULL,
    amount_forms     varchar(200)  NOT NULL    -- how the amount cells were stored, with counts
);
GO

IF OBJECT_ID(N'raw.oscar_bud', N'U') IS NULL
BEGIN
    CREATE TABLE raw.oscar_bud (
        file_id        int            NOT NULL,   -- raw.oscar_bud_file
        source_row     int            NOT NULL,   -- row number in the sheet (header = 1)
        vintage        varchar(7)     NOT NULL,
        year_no                                  nvarchar(20) NOT NULL,
        year_short_name                          nvarchar(20) NOT NULL,
        quarter_short_name                       nvarchar(20) NOT NULL,
        month_short_name                         nvarchar(20) NOT NULL,
        budgeting_organisations_code             nvarchar(20) NOT NULL,
        department_group_code                    nvarchar(20) NOT NULL,
        department_group_long_name               nvarchar(200) NOT NULL,
        organisation_code                        nvarchar(20) NOT NULL,
        organisation_long_name                   nvarchar(200) NOT NULL,
        organisation_type_code                   nvarchar(20) NOT NULL,
        organisation_type_long_name              nvarchar(50) NOT NULL,
        organisation_type_l1_code                nvarchar(20) NOT NULL,
        organisation_type_l1_long_name           nvarchar(100) NOT NULL,
        pesa_group_code                          nvarchar(20) NOT NULL,
        pesa_group_long_name                     nvarchar(100) NOT NULL,
        sr_group_code                            nvarchar(20) NOT NULL,
        sr_group_long_name                       nvarchar(100) NOT NULL,
        bx_validation_group_code                 nvarchar(20) NOT NULL,
        bx_validation_group_long_name            nvarchar(20) NOT NULL,
        fo_validation_group_code                 nvarchar(20) NOT NULL,
        fo_validation_group_long_name            nvarchar(100) NOT NULL,
        accounting_arrangements_code             nvarchar(20) NOT NULL,
        accounting_arrangements_long_name        nvarchar(20) NOT NULL,
        counter_organisation_code                nvarchar(20) NOT NULL,
        counter_organisation_long_name           nvarchar(20) NOT NULL,
        segment_l4_code                          nvarchar(20) NOT NULL,
        segment_l4_long_name                     nvarchar(400) NOT NULL,
        cofog_l0_code                            nvarchar(20) NOT NULL,
        cofog_l0_long_name                       nvarchar(100) NOT NULL,
        cofog_l1_code                            nvarchar(20) NOT NULL,
        cofog_l1_long_name                       nvarchar(200) NOT NULL,
        cofog_l2_code                            nvarchar(20) NOT NULL,
        cofog_l2_long_name                       nvarchar(100) NOT NULL,
        control_budget_l0_long_name              nvarchar(20) NOT NULL,
        control_budget_l1_long_name              nvarchar(20) NOT NULL,
        coverage_long_name                       nvarchar(20) NOT NULL,
        estimates_row_code                       nvarchar(20) NOT NULL,
        estimates_row_long_name                  nvarchar(400) NOT NULL,
        net_subhead_long_name                    nvarchar(20) NOT NULL,
        pesa11_code                              nvarchar(50) NOT NULL,
        pesa_la_grants_code                      nvarchar(50) NOT NULL,
        pesa_lg_code                             nvarchar(20) NOT NULL,
        pesa_services_long_name                  nvarchar(20) NOT NULL,
        pesa_regional_code                       nvarchar(20) NOT NULL,
        policy_ringfence_code                    nvarchar(100) NOT NULL,
        accounting_authority_l0_code             nvarchar(50) NOT NULL,
        accounting_authority_l1_long_name        nvarchar(20) NOT NULL,
        sub_function_code                        nvarchar(20) NOT NULL,
        sub_function_long_name                   nvarchar(200) NOT NULL,
        function_code                            nvarchar(20) NOT NULL,
        function_long_name                       nvarchar(100) NOT NULL,
        accounts_long_name                       nvarchar(20) NOT NULL,
        chart_of_accounts_l5_code                nvarchar(20) NOT NULL,
        chart_of_accounts_l5_long_name           nvarchar(400) NOT NULL,
        economic_budget_code                     nvarchar(100) NOT NULL,
        economic_ringfence_code                  nvarchar(100) NOT NULL,
        economic_group_code                      nvarchar(20) NOT NULL,
        economic_group_long_name                 nvarchar(100) NOT NULL,
        economic_category_code                   nvarchar(20) NOT NULL,
        economic_category_long_name              nvarchar(100) NOT NULL,
        sector_code                              nvarchar(20) NOT NULL,
        sector_long_name                         nvarchar(20) NOT NULL,
        tes_code                                 nvarchar(20) NOT NULL,
        tes_long_name                            nvarchar(20) NOT NULL,
        esa_code                                 nvarchar(20) NOT NULL,
        esa_long_name                            nvarchar(200) NOT NULL,
        esa_group_code                           nvarchar(20) NOT NULL,
        esa_group_long_name                      nvarchar(100) NOT NULL,
        psat_code                                nvarchar(100) NOT NULL,
        psat_long_name                           nvarchar(100) NOT NULL,
        na_aggregate_code                        nvarchar(20) NOT NULL,
        na_aggregate_long_name                   nvarchar(100) NOT NULL,
        estimates_category_code                  nvarchar(50) NOT NULL,
        estimates_sub_category_code              nvarchar(50) NOT NULL,
        estimates_column_code                    nvarchar(20) NOT NULL,
        pesa_economic_budget_code                nvarchar(20) NOT NULL,
        pesa_economic_group_code                 nvarchar(100) NOT NULL,
        income_category_short_name               nvarchar(50) NOT NULL,
        usage_code                               nvarchar(20) NOT NULL,
        status_code                              nvarchar(20) NOT NULL,
        type_code                                nvarchar(50) NOT NULL,
        type_long_name                           nvarchar(100) NOT NULL,
        type_group_code                          nvarchar(50) NOT NULL,
        type_group_long_name                     nvarchar(50) NOT NULL,
        version_code                             nvarchar(20) NOT NULL,
        fct_load_type_code                       nvarchar(20) NOT NULL,
        fct_load_type_long_name                  nvarchar(20) NOT NULL,
        row_description                          nvarchar(20) NOT NULL,
        data_id                                  nvarchar(20) NOT NULL,
        data_effective_datetime                  nvarchar(20) NOT NULL,
        amount_text    nvarchar(100)  NOT NULL,   -- AMOUNT as read, GBP thousands
        amount         decimal(38,10) NOT NULL    -- the same value, exact
    );
    CREATE CLUSTERED COLUMNSTORE INDEX cci_raw_oscar_bud ON raw.oscar_bud;
END;
GO

IF OBJECT_ID(N'raw.oscar_bud_control_expected', N'U') IS NULL
CREATE TABLE raw.oscar_bud_control_expected (
    vintage                          varchar(7)     NOT NULL,
    filename                         nvarchar(260)  NOT NULL,
    sha256                           char(64)       NOT NULL,
    financial_year                   varchar(7)     NOT NULL,
    total_rows                       int            NOT NULL,
    blank_rows                       int            NOT NULL,
    data_rows                        int            NOT NULL,
    closed_rows                      int            NOT NULL,
    closed_rows_with_identical_twin  int            NOT NULL,
    amount_sum_all_rows              decimal(38,10) NOT NULL,
    amount_sum_excluding_closed      decimal(38,10) NOT NULL,
    amount_closed                    decimal(38,10) NOT NULL,
    amount_del                       decimal(38,10) NOT NULL,   -- excluding Closed rows
    amount_ame                       decimal(38,10) NOT NULL,
    amount_non_budget                decimal(38,10) NOT NULL,
    amount_other_control_budget      decimal(38,10) NOT NULL,
    CONSTRAINT pk_raw_oscar_bud_control_expected PRIMARY KEY (vintage, filename)
);
GO

IF OBJECT_ID(N'raw.oscar_bud_independent_expected', N'U') IS NULL
CREATE TABLE raw.oscar_bud_independent_expected (
    vintage                      varchar(7)     NOT NULL,
    filename                     nvarchar(260)  NOT NULL,
    sha256                       char(64)       NOT NULL,
    financial_year               varchar(7)     NOT NULL,
    total_rows                   int            NOT NULL,
    blank_rows                   int            NOT NULL,
    data_rows                    int            NOT NULL,
    closed_rows                  int            NOT NULL,
    amount_sum_all_rows          decimal(38,10) NOT NULL,
    amount_sum_excluding_closed  decimal(38,10) NOT NULL,
    amount_closed                decimal(38,10) NOT NULL,
    CONSTRAINT pk_raw_oscar_bud_independent_expected PRIMARY KEY (vintage, filename)
);
GO
