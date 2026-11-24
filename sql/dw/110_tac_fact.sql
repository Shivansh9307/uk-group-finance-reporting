-- scope: full
-- dw.tac_fact: the statutory statements of the NHS trusts and foundation trusts, one row per provider, file
-- year, line and column.
--   release         the year of the file the value is read from, 2024-25
--   period_column   CY the file's own year, PY the prior-year column as published in that file. The PY column of
--                   a statement of financial position is the opening balance; the PY column of year Y is
--                   compared with the CY column of year Y-1 in audit.tac_prior_year_difference
--   reported_year   the financial year the value is about: the release for CY, the year before it for PY
--   value           DECIMAL(19,4), thousands of pounds, as published (the files carry up to five decimal
--                   places; the fifth is rounded away, and audit.tac_file_control_totals tests the sums)
-- Grain: (provider_key, release, line_key, period_column). A value whose provider or line cannot be found is not
-- here: it is in quarantine.tac_unmapped_row (sql/dw/120).
-- Every row is a real published value, including the zeros the forms are filled with.

DROP TABLE IF EXISTS dw.tac_fact;
GO

CREATE TABLE dw.tac_fact (
    provider_key   int           NOT NULL,
    release        varchar(7)    NOT NULL,
    line_key       int           NOT NULL,
    period_column  char(2)       NOT NULL,
    reported_year  varchar(7)    NOT NULL,
    value          decimal(19,4) NOT NULL,
    file_id        int           NOT NULL,
    source_row     int           NOT NULL,
    CONSTRAINT pk_dw_tac_fact PRIMARY KEY (provider_key, release, line_key, period_column),
    CONSTRAINT uq_dw_tac_fact_source UNIQUE (file_id, source_row),
    CONSTRAINT fk_dw_tac_fact_provider FOREIGN KEY (provider_key) REFERENCES dw.tac_provider (provider_key),
    CONSTRAINT fk_dw_tac_fact_line FOREIGN KEY (line_key) REFERENCES dw.tac_statutory_line (line_key)
);
GO

INSERT INTO dw.tac_fact (provider_key, release, line_key, period_column, reported_year, value, file_id, source_row)
SELECT p.provider_key, v.release, l.line_key, v.period_column,
       CASE v.period_column WHEN 'CY' THEN v.release
            ELSE CONCAT(CAST(LEFT(v.release, 4) AS int) - 1, '-', RIGHT(CONCAT('0', CAST(SUBSTRING(v.release, 6, 2) AS int) - 1), 2)) END,
       v.value, v.file_id, v.source_row
FROM stg.tac_value AS v
JOIN stg.tac_provider_year AS y ON y.file_id = v.file_id AND y.data_name_key = v.name_key
JOIN dw.tac_provider AS p ON p.provider_code = y.provider_code
JOIN dw.tac_statutory_line AS l ON l.statement = v.statement AND l.sub_code = v.sub_code;
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'NHS TAC statement values (real, GBP thousand, as published) by provider, year, line and current or prior-year column. No authored or synthetic value.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'tac_fact';
GO
