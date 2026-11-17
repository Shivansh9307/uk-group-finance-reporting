-- dw.plan_coverage: what dw.fact_plan holds, by plan source, financial year, measure and grain, and the number of
-- fact rows each plan source contributes (dw.dim_plan_source.fact_plan_rows). Runs after the fact is complete,
-- including the OSCAR rows that a full-scope build adds in dw/525.

DROP TABLE IF EXISTS dw.plan_coverage;
GO

UPDATE ps SET fact_plan_rows = c.n
FROM dw.dim_plan_source AS ps
JOIN (SELECT plan_source_key, COUNT(*) AS n FROM dw.fact_plan GROUP BY plan_source_key) AS c
  ON c.plan_source_key = ps.plan_source_key;
GO

CREATE TABLE dw.plan_coverage (
    plan_source_key  int            NOT NULL,
    financial_year   varchar(7)     NOT NULL,
    measure          varchar(40)    NOT NULL,
    grain_code       char(1)        NOT NULL,
    row_count        int            NOT NULL,
    source_line_count int           NOT NULL,
    amount_total     decimal(19,4)  NOT NULL,    -- GBP thousands; part measures (ADMIN) are not part of the DEL totals
    CONSTRAINT pk_dw_plan_coverage PRIMARY KEY (plan_source_key, financial_year, measure, grain_code),
    CONSTRAINT fk_dw_plan_coverage_source FOREIGN KEY (plan_source_key) REFERENCES dw.dim_plan_source (plan_source_key)
);
GO

INSERT INTO dw.plan_coverage (plan_source_key, financial_year, measure, grain_code, row_count, source_line_count, amount_total)
SELECT plan_source_key, financial_year, measure, grain_code, COUNT(*), SUM(source_line_count), SUM(amount)
FROM dw.fact_plan
GROUP BY plan_source_key, financial_year, measure, grain_code;
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'What fact_plan holds: rows, source lines and totals by plan source, financial year, measure and grain.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'plan_coverage';
GO
