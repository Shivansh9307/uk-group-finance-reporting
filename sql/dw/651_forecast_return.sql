-- scope: full
-- dw.forecast_return: the departments' monthly returns to HM Treasury, FY2017-18 to FY2022-23, 83 returns.
-- Grain: financial year x return number x organisation code x economic category x control budget detail x economic budget x
-- period. A return is R0 (before the year) to R12 (during it) and R13 (final outturn). Periods 1 to 12 are April to March;
-- period 0 holds budget adjustments only (it exists in R13 of the annual extracts) and is kept, flagged, and never part of
-- a return's total.
--   amount           GBP thousands, DECIMAL(19,4), spending positive, income negative: the exact cell sums of
--                    stg.forecast_return_cell added up and rounded once to four places. Statuses (Confirmed, Locked, DRAFT)
--                    and types are all added: a return's total is every status (test 652 shows no organisation is both DRAFT
--                    and CONFIRMED in one return).
--   forecast_status  the rule: in return n month m is actual when m <= n and forecast when m > n; month m = n is the month the
--                    return has just closed and is flagged provisional. R0 is all forecast, R13 is all actual. Period 0 is
--                    'adjustment'. A row has exactly one of 'actual', 'provisional', 'forecast', 'adjustment'.
--   is_actual        1 for 'actual' and 'provisional' (m <= n, months 1 to 12)
--   is_provisional   1 where m = n and n is 1 to 12
--   budget_measure   RDEL = DEL programme or administration, resource (depreciation included, as OSCAR reports it);
--                    CDEL = DEL, capital; AME = departmental AME, resource and capital together; OTHER = non-departmental AME,
--                    non-budget, and DEL lines whose economic budget is n/a. The forecast and accuracy tables use the first three.
--   department_group_code / name  the department as the return reports it (the group of the organisation in that return)
--   organisation_key, durable_key, department_key  from dw.forecast_return_org_map
--   includes_draft   1 if any source cell of this row had status DRAFT
-- No foreign keys to the dimensions: a post-only rebuild drops and recreates them first, and sql/tests/654 checks the keys.
-- A row whose organisation code has no organisation key is not here: it is in quarantine.forecast_return_unmapped (sql/dw/652).

DROP TABLE IF EXISTS dw.forecast_return;
GO

CREATE TABLE dw.forecast_return (
    financial_year          varchar(7)     NOT NULL,
    return_no               tinyint        NOT NULL,
    organisation_code       nvarchar(50)   NOT NULL,
    economic_category_code  nvarchar(50)   NOT NULL,
    control_budget_detail   varchar(30)    NOT NULL,
    economic_budget         nvarchar(50)   NOT NULL,
    period                  tinyint        NOT NULL,
    organisation_key        int            NOT NULL,
    durable_key             nvarchar(30)   NOT NULL,
    department_key          int            NOT NULL,
    department_group_code   nvarchar(50)   NOT NULL,
    department_group_name   nvarchar(400)  NOT NULL,
    sr_group_code           nvarchar(50)   NOT NULL,
    budget_measure          varchar(5)     NOT NULL,
    forecast_status         varchar(11)    NOT NULL,
    is_actual               bit            NOT NULL,
    is_provisional          bit            NOT NULL,
    is_period_zero          bit            NOT NULL,
    includes_draft          bit            NOT NULL,
    amount                  decimal(19,4)  NOT NULL,
    source_rows             int            NOT NULL,
    source_cells            int            NOT NULL,
    CONSTRAINT pk_dw_forecast_return PRIMARY KEY
        (financial_year, return_no, period, organisation_code, economic_category_code, control_budget_detail, economic_budget),
    CONSTRAINT ck_dw_forecast_return_status CHECK (forecast_status IN ('actual', 'provisional', 'forecast', 'adjustment'))
);
GO

INSERT INTO dw.forecast_return
    (financial_year, return_no, organisation_code, economic_category_code, control_budget_detail, economic_budget, period,
     organisation_key, durable_key, department_key, department_group_code, department_group_name, sr_group_code,
     budget_measure, forecast_status, is_actual, is_provisional, is_period_zero, includes_draft, amount, source_rows, source_cells)
SELECT
    g.financial_year, g.return_no, g.organisation_code, g.economic_category_code, g.control_budget_detail, g.economic_budget, g.period,
    m.organisation_key, m.durable_key, m.department_key, g.department_group_code, g.department_group_name, g.sr_group_code,
    CASE WHEN g.control_budget_detail IN ('DEL PROG', 'DEL ADMIN') AND g.economic_budget = 'RESOURCE' THEN 'RDEL'
         WHEN g.control_budget_detail IN ('DEL PROG', 'DEL ADMIN') AND g.economic_budget = 'CAPITAL' THEN 'CDEL'
         WHEN g.control_budget_detail = 'DEPT AME' THEN 'AME'
         ELSE 'OTHER' END,
    CASE WHEN g.period = 0 THEN 'adjustment'
         WHEN g.period < g.return_no THEN 'actual'
         WHEN g.period = g.return_no THEN 'provisional'
         ELSE 'forecast' END,
    CASE WHEN g.period BETWEEN 1 AND 12 AND g.period <= g.return_no THEN 1 ELSE 0 END,
    CASE WHEN g.period = g.return_no AND g.return_no BETWEEN 1 AND 12 THEN 1 ELSE 0 END,
    CASE WHEN g.period = 0 THEN 1 ELSE 0 END,
    g.includes_draft,
    CAST(ROUND(g.amount_exact, 4) AS decimal(19, 4)),
    g.source_rows, g.source_cells
FROM (
    SELECT c.financial_year, c.return_no, c.period, c.organisation_code, c.economic_category_code, c.control_budget_detail,
           c.economic_budget, MIN(c.department_group_code) AS department_group_code,
           MIN(c.department_group_name) AS department_group_name, MIN(c.sr_group_code) AS sr_group_code,
           MAX(CASE WHEN c.status_code = 'DRAFT' THEN 1 ELSE 0 END) AS includes_draft,
           SUM(c.amount_exact) AS amount_exact, SUM(c.source_rows) AS source_rows, COUNT(*) AS source_cells
    FROM stg.forecast_return_cell AS c
    GROUP BY c.financial_year, c.return_no, c.period, c.organisation_code, c.economic_category_code, c.control_budget_detail,
             c.economic_budget
) AS g
JOIN dw.forecast_return_org_map AS m ON m.financial_year = g.financial_year AND m.organisation_code = g.organisation_code
ORDER BY g.financial_year, g.return_no, g.period, g.organisation_code, g.economic_category_code, g.control_budget_detail,
         g.economic_budget;
GO
