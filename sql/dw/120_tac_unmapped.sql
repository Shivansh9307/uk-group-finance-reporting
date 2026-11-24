-- scope: full
-- quarantine.tac_unmapped_row: statement values that are loaded and typed but cannot enter dw.tac_fact, with the
-- reason. In the real files there are none (a test pins the count). Nothing is dropped silently:
--   provider_not_listed   the data sheet names a provider that the file's list of providers does not (by name key)
--   line_not_in_form      the sub code is not a line of that statement in any illustrative form
-- The table is built here, after the fact, because it is the difference between stg.tac_value and the fact.

DROP TABLE IF EXISTS quarantine.tac_unmapped_row;
GO

CREATE TABLE quarantine.tac_unmapped_row (
    file_id        int           NOT NULL,
    source_row     int           NOT NULL,
    reason_code    varchar(30)   NOT NULL,
    name_key       nvarchar(400) NOT NULL,
    statement      varchar(4)    NOT NULL,
    sub_code       varchar(20)   NOT NULL,
    value          decimal(19,4) NOT NULL,
    CONSTRAINT pk_quarantine_tac_unmapped_row PRIMARY KEY (file_id, source_row)
);
GO

INSERT INTO quarantine.tac_unmapped_row (file_id, source_row, reason_code, name_key, statement, sub_code, value)
SELECT v.file_id, v.source_row,
       CASE WHEN y.provider_code IS NULL THEN 'provider_not_listed' ELSE 'line_not_in_form' END,
       v.name_key, v.statement, v.sub_code, v.value
FROM stg.tac_value AS v
LEFT JOIN stg.tac_provider_year AS y ON y.file_id = v.file_id AND y.data_name_key = v.name_key
WHERE NOT EXISTS (SELECT 1 FROM dw.tac_fact AS f WHERE f.file_id = v.file_id AND f.source_row = v.source_row);
GO
