-- phase: pre
-- scope: full
-- Rows the BUD and PSS loads reject, with the reason and the row as text. The real files have none.
-- Reasons: amount_blank, amount_scale (more than 10 decimal places), amount_range.

IF OBJECT_ID(N'quarantine.oscar_bud', N'U') IS NULL
CREATE TABLE quarantine.oscar_bud (
    file_id         int            NOT NULL,
    source_row      int            NOT NULL,
    vintage         varchar(7)     NOT NULL,
    reason_code     varchar(30)    NOT NULL,
    reason_detail   nvarchar(400)  NOT NULL,
    amount_text     nvarchar(100)  NOT NULL,
    row_json        nvarchar(max)  NOT NULL,   -- every column of the row as read
    CONSTRAINT pk_quarantine_oscar_bud PRIMARY KEY (file_id, source_row)
);
GO

IF OBJECT_ID(N'quarantine.pss', N'U') IS NULL
CREATE TABLE quarantine.pss (
    file_id         int            NOT NULL,
    source_row      int            NOT NULL,
    reason_code     varchar(30)    NOT NULL,
    reason_detail   nvarchar(400)  NOT NULL,
    amount_text     nvarchar(100)  NOT NULL,
    row_json        nvarchar(max)  NOT NULL,
    CONSTRAINT pk_quarantine_pss PRIMARY KEY (file_id, source_row)
);
GO
