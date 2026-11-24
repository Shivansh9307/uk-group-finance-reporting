-- phase: pre
-- scope: full
-- Cells of the workforce files that are not numbers, with the reason (written by ukfr.stages.workforce).
-- Rows that cannot be placed (no organisation name, an organisation with no map row) are quarantined later, in SQL
-- (sql/dw/606_workforce_row_quarantine.sql), because that is a business decision.

IF OBJECT_ID(N'quarantine.workforce_value', N'U') IS NULL
CREATE TABLE quarantine.workforce_value (
    file_id        int            NOT NULL,
    source_row     int            NOT NULL,
    column_index   int            NOT NULL,
    measure_key    varchar(60)    NOT NULL,
    column_label   nvarchar(400)  NOT NULL,
    value_text     nvarchar(100)  NOT NULL,
    reason_code    varchar(40)    NOT NULL,   -- not_a_number
    reason_detail  nvarchar(400)  NOT NULL,
    CONSTRAINT pk_quarantine_workforce_value PRIMARY KEY (file_id, source_row, column_index)
);
GO
