-- scope: full
-- The landed forecast-return cells, typed and with the control budget detail in the spelling the in-year releases use.
-- One row per raw.forecast_return_cell (same cell_id), so nothing is added or dropped here.
--   control_budget_detail  DEL PROG | DEL ADMIN | DEPT AME | NON-DEPT AME | NON-BUDGET. The annual extracts write the detail
--                          as a long name in control_budget_l1_name; the MFO csv files write it in control_budget_l0_name
--                          (and the top level in l1). A name that is neither is left NULL and a test fails the build.
--   amount_exact           the exact sum of the cell's source amounts, DECIMAL(38,16), GBP thousands
--   amount                 amount_exact rounded to four decimal places, DECIMAL(19,4), GBP thousands (spending positive)
-- Needs the annual extracts and the MFO zips, so this file runs in a full-scope build only.

DROP TABLE IF EXISTS stg.forecast_return_cell;
GO

CREATE TABLE stg.forecast_return_cell (
    cell_id                 int            NOT NULL,
    file_id                 int            NOT NULL,
    family                  varchar(10)    NOT NULL,
    financial_year          varchar(7)     NOT NULL,
    return_no               int            NOT NULL,
    period                  int            NOT NULL,
    status_code             nvarchar(50)   NOT NULL,
    type_code               nvarchar(50)   NOT NULL,
    department_group_code   nvarchar(50)   NOT NULL,
    department_group_name   nvarchar(400)  NOT NULL,
    sr_group_code           nvarchar(50)   NOT NULL,
    organisation_code       nvarchar(50)   NOT NULL,
    organisation_name       nvarchar(400)  NOT NULL,
    economic_category_code  nvarchar(50)   NOT NULL,
    control_budget_detail   varchar(30)    NULL,
    economic_budget         nvarchar(50)   NOT NULL,
    amount_exact            decimal(38,16) NOT NULL,
    amount                  decimal(19,4)  NOT NULL,
    source_rows             int            NOT NULL,
    first_line              int            NOT NULL,
    last_line               int            NOT NULL,
    CONSTRAINT pk_stg_forecast_return_cell PRIMARY KEY (cell_id)
);
GO

INSERT INTO stg.forecast_return_cell
    (cell_id, file_id, family, financial_year, return_no, period, status_code, type_code, department_group_code,
     department_group_name, sr_group_code, organisation_code, organisation_name, economic_category_code,
     control_budget_detail, economic_budget, amount_exact, amount, source_rows, first_line, last_line)
SELECT
    c.cell_id, c.file_id, f.family, f.financial_year, c.return_no, c.period, c.status_code, c.type_code,
    c.department_group_code, c.department_group_name, c.sr_group_code, c.organisation_code, c.organisation_name,
    c.economic_category_code,
    CASE WHEN c.control_budget_l0_name IN ('DEL PROG', 'DEL ADMIN', 'DEPT AME', 'NON-DEPT AME', 'NON-BUDGET')
              THEN c.control_budget_l0_name
         WHEN c.control_budget_l1_name = 'DEPARTMENTAL EXPENDITURE LIMITS PROGRAMME' THEN 'DEL PROG'
         WHEN c.control_budget_l1_name = 'DEPARTMENTAL EXPENDITURE LIMITS ADMINISTRATION' THEN 'DEL ADMIN'
         WHEN c.control_budget_l1_name = 'DEPARTMENTAL ANNUALLY MANAGED EXPENDITURE' THEN 'DEPT AME'
         WHEN c.control_budget_l1_name = 'NON-DEPARTMENTAL ANNUALLY MANAGED EXPENDITURE' THEN 'NON-DEPT AME'
         WHEN c.control_budget_l1_name = 'NON-BUDGET (NB)' THEN 'NON-BUDGET'
    END,
    c.economic_budget_code, c.amount, CAST(ROUND(c.amount, 4) AS decimal(19, 4)),
    c.source_rows, c.first_line, c.last_line
FROM raw.forecast_return_cell AS c
JOIN raw.forecast_return_file AS f ON f.file_id = c.file_id;
GO

CREATE INDEX ix_stg_forecast_return_cell_return
    ON stg.forecast_return_cell (financial_year, return_no, period, organisation_code);
GO
