-- scope: full
-- stg.tac_value: the statement values of the 12 data files, typed. One row per raw row.
--   statement       SoCI | SoFP | SoCF, from the worksheet name
--   table_id        the block of the form (the income statement has two)
--   period_column   CY the year of the file, PY the prior-year column as published in that file
--   value           DECIMAL(19,4), thousands of pounds, as published (income and assets positive for the
--                   statements' expected signs; this is not the OSCAR sign)
--   value_exact     the raw value, up to five decimal places in the files
-- A main code is A<sheet><CY|PY><column>; the sheet number must agree with the worksheet name (a test).

DROP TABLE IF EXISTS stg.tac_value;
GO

CREATE TABLE stg.tac_value (
    file_id        int            NOT NULL,
    source_row     int            NOT NULL,
    release        varchar(7)     NOT NULL,
    provider_type  varchar(30)    NOT NULL,
    name_key       nvarchar(400)  NOT NULL,
    statement      varchar(4)     NOT NULL,
    worksheet_name nvarchar(60)   NOT NULL,
    table_id       tinyint        NOT NULL,
    main_code      varchar(20)    NOT NULL,
    period_column  char(2)        NOT NULL,
    form_row       int            NOT NULL,
    sub_code       varchar(20)    NOT NULL,
    value          decimal(19,4)  NOT NULL,
    value_exact    decimal(38,10) NOT NULL,
    CONSTRAINT pk_stg_tac_value PRIMARY KEY (file_id, source_row),
    CONSTRAINT ck_stg_tac_value_period CHECK (period_column IN ('CY', 'PY')),
    CONSTRAINT ck_stg_tac_value_statement CHECK (statement IN ('SoCI', 'SoFP', 'SoCF'))
);
GO

INSERT INTO stg.tac_value
    (file_id, source_row, release, provider_type, name_key, statement, worksheet_name, table_id, main_code,
     period_column, form_row, sub_code, value, value_exact)
SELECT v.file_id, v.source_row, f.release, f.provider_type, n.name_key,
       CASE LEFT(v.worksheet_name, 5) WHEN 'TAC02' THEN 'SoCI' WHEN 'TAC03' THEN 'SoFP' WHEN 'TAC05' THEN 'SoCF' END,
       v.worksheet_name, CAST(v.table_id AS tinyint), v.main_code, SUBSTRING(v.main_code, 4, 2),
       CAST(v.row_number AS int), v.sub_code, CAST(v.value AS decimal(19,4)), v.value
FROM raw.tac_value AS v
JOIN raw.tac_file AS f ON f.file_id = v.file_id
JOIN stg.tac_data_name AS n ON n.file_id = v.file_id AND n.organisation_name = v.organisation_name;
GO
