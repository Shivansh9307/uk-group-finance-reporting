-- phase: pre
-- scope: full
-- Rows the TAC load rejects, with the reason and the row as text. The real files have none.
-- Reasons: value_blank, value_scale (more than 10 decimal places), value_range.
-- Rows that load but cannot be given a provider are quarantined later, by sql/dw/130_tac_unmapped.sql.

IF OBJECT_ID(N'quarantine.tac_value', N'U') IS NULL
CREATE TABLE quarantine.tac_value (
    file_id         int            NOT NULL,
    source_row      int            NOT NULL,
    reason_code     varchar(30)    NOT NULL,
    reason_detail   nvarchar(400)  NOT NULL,
    value_text      nvarchar(100)  NOT NULL,
    row_json        nvarchar(max)  NOT NULL,
    CONSTRAINT pk_quarantine_tac_value PRIMARY KEY (file_id, source_row)
);
GO
