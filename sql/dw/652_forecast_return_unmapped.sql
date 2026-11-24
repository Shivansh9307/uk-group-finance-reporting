-- scope: full
-- quarantine.forecast_return_unmapped: the cells of stg.forecast_return_cell whose organisation code (in that financial
-- year) has no row in dw.forecast_return_org_map, so that they cannot be given a durable organisation key. They are not
-- in dw.forecast_return, and every one is kept here with the reason. Nothing is dropped: a test requires the cells in
-- dw.forecast_return plus the cells here to equal the cells staged, and the exact amounts to agree.
-- The file is in the dw layer because the table is derived from stg and dw tables, which exist only after the stg layer.

DROP TABLE IF EXISTS quarantine.forecast_return_unmapped;
GO

CREATE TABLE quarantine.forecast_return_unmapped (
    cell_id                 int            NOT NULL,
    financial_year          varchar(7)     NOT NULL,
    return_no               int            NOT NULL,
    period                  int            NOT NULL,
    organisation_code       nvarchar(50)   NOT NULL,
    organisation_name       nvarchar(400)  NOT NULL,
    department_group_code   nvarchar(50)   NOT NULL,
    economic_category_code  nvarchar(50)   NOT NULL,
    control_budget_detail   varchar(30)    NULL,
    economic_budget         nvarchar(50)   NOT NULL,
    amount_exact            decimal(38,16) NOT NULL,
    reason_code             varchar(30)    NOT NULL,
    reason_detail           nvarchar(400)  NOT NULL,
    CONSTRAINT pk_quarantine_forecast_return_unmapped PRIMARY KEY (cell_id)
);
GO

INSERT INTO quarantine.forecast_return_unmapped
    (cell_id, financial_year, return_no, period, organisation_code, organisation_name, department_group_code,
     economic_category_code, control_budget_detail, economic_budget, amount_exact, reason_code, reason_detail)
SELECT c.cell_id, c.financial_year, c.return_no, c.period, c.organisation_code, c.organisation_name, c.department_group_code,
       c.economic_category_code, c.control_budget_detail, c.economic_budget, c.amount_exact,
       'no organisation key',
       N'organisation code ' + c.organisation_code + N' in ' + c.financial_year
         + N' is not a code of dw.dim_organisation and its three-letter prefix is not the durable key of a body in it'
FROM stg.forecast_return_cell AS c
WHERE NOT EXISTS (SELECT 1 FROM dw.forecast_return_org_map AS m
                  WHERE m.financial_year = c.financial_year AND m.organisation_code = c.organisation_code);
GO
