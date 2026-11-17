-- phase: pre
-- Rows the in-year load rejected, with the reason and the text exactly as read.

IF OBJECT_ID(N'quarantine.oscar_inyear', N'U') IS NULL
CREATE TABLE quarantine.oscar_inyear (
    file_id                      int            NOT NULL,
    source_row                   int            NOT NULL,
    release                      varchar(7)     NOT NULL,
    reason_code                  varchar(40)    NOT NULL,
    reason_detail                nvarchar(400)  NOT NULL,
    organisation_code            nvarchar(50)   NOT NULL,
    organisation_name            nvarchar(400)  NOT NULL,
    control_budget_code          nvarchar(100)  NOT NULL,
    control_budget_detail_code   nvarchar(100)  NOT NULL,
    department_name              nvarchar(400)  NOT NULL,
    sub_segment_code             nvarchar(50)   NOT NULL,
    sub_segment_name             nvarchar(1000) NOT NULL,
    economic_category_code       nvarchar(50)   NOT NULL,
    economic_category_name       nvarchar(400)  NOT NULL,
    economic_budget_code         nvarchar(100)  NOT NULL,
    pesa_economic_group_code     nvarchar(400)  NOT NULL,
    pesa_economic_group_name     nvarchar(400)  NOT NULL,
    version                      nvarchar(400)  NOT NULL,
    [year]                       nvarchar(100)  NOT NULL,
    quarter                      nvarchar(100)  NOT NULL,
    [month]                      nvarchar(100)  NOT NULL,
    amount_text                  nvarchar(100)  NOT NULL,
    CONSTRAINT pk_quarantine_oscar_inyear PRIMARY KEY (file_id, source_row)
);
GO
