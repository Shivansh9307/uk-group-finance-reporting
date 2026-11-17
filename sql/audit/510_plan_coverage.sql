-- audit.plan_coverage: dw.plan_coverage with readable codes, so that it is written to evidence/build.
-- Year x plan source x measure x grain, with the number of fact rows, the published lines or extract rows
-- behind them and the total in GBP thousands. In a committed-scope build the OSCAR rows are absent.

DROP TABLE IF EXISTS audit.plan_coverage;
GO

CREATE TABLE audit.plan_coverage (
    plan_source_code   varchar(40)    NOT NULL,
    financial_year     varchar(7)     NOT NULL,
    measure            varchar(40)    NOT NULL,
    grain_code         char(1)        NOT NULL,
    row_count          int            NOT NULL,
    source_line_count  int            NOT NULL,
    amount_total       decimal(19,4)  NOT NULL,
    CONSTRAINT pk_audit_plan_coverage PRIMARY KEY (plan_source_code, financial_year, measure, grain_code)
);
GO

INSERT INTO audit.plan_coverage (plan_source_code, financial_year, measure, grain_code, row_count, source_line_count, amount_total)
SELECT s.plan_source_code, c.financial_year, c.measure, c.grain_code, c.row_count, c.source_line_count, c.amount_total
FROM dw.plan_coverage AS c
JOIN dw.dim_plan_source AS s ON s.plan_source_key = c.plan_source_key;
GO
