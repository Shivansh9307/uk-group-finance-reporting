-- scope: full
-- The elimination-gap control: the sum of the provider accounts against the consolidated NHS provider accounts, in
-- which intra-NHS balances are eliminated.
--   dw.tac_control_line          AUTHORED. The six headline lines of the control (authored/tac_control_line.csv): label,
--                                statement, whether it is a flow of the year or a balance at its end
--   dw.tac_control_member        AUTHORED. Which provider statement lines (never a subtotal or a total) make up each
--                                control line
--   dw.tac_consolidated_control  AUTHORED, hand-keyed. The values printed in the consolidated statements, one row per
--                                printed line and year, with the page of each (authored/tac_consolidated_control.csv).
--                                amount_gbp_million is as printed; amount is the same in GBP thousands, the unit of the
--                                provider amounts, on the TAC sign (income and assets positive, expenses and
--                                liabilities negative, as printed)
-- These tables hold the only authored amounts of the TAC objects. No real total reads them (a test says so): the gap
-- is a comparison of the two sides, never a sum of them.

DROP TABLE IF EXISTS dw.tac_consolidated_control;
GO
DROP TABLE IF EXISTS dw.tac_control_member;
GO
DROP TABLE IF EXISTS dw.tac_control_line;
GO

CREATE TABLE dw.tac_control_line (
    control_line_key  int            NOT NULL CONSTRAINT pk_dw_tac_control_line PRIMARY KEY,
    control_line      varchar(30)    NOT NULL CONSTRAINT uq_dw_tac_control_line_code UNIQUE,
    label             nvarchar(100)  NOT NULL,
    statement         varchar(4)     NOT NULL,
    nature            varchar(10)    NOT NULL,
    note              nvarchar(1000) NOT NULL
);
GO
CREATE TABLE dw.tac_control_member (
    control_line_key  int            NOT NULL,
    line_key          int            NOT NULL,
    CONSTRAINT pk_dw_tac_control_member PRIMARY KEY (control_line_key, line_key),
    CONSTRAINT fk_dw_tac_control_member_line FOREIGN KEY (control_line_key) REFERENCES dw.tac_control_line (control_line_key)
);
GO
CREATE TABLE dw.tac_consolidated_control (
    release                              varchar(7)     NOT NULL,
    printed_line                         varchar(40)    NOT NULL,
    control_line_key                     int            NOT NULL,
    statement                            varchar(4)     NOT NULL,
    label                                nvarchar(100)  NOT NULL,
    amount_gbp_million                   decimal(19,4)  NOT NULL,
    amount                               decimal(19,4)  NOT NULL,
    next_report_comparative_gbp_million  decimal(19,4)  NULL,
    source_report                        nvarchar(200)  NOT NULL,
    pdf_page                             int            NOT NULL,
    printed_page                         int            NOT NULL,
    note                                 nvarchar(1000) NOT NULL,
    CONSTRAINT pk_dw_tac_consolidated_control PRIMARY KEY (release, printed_line),
    CONSTRAINT fk_dw_tac_consolidated_control_line FOREIGN KEY (control_line_key) REFERENCES dw.tac_control_line (control_line_key)
);
GO

INSERT INTO dw.tac_control_line (control_line_key, control_line, label, statement, nature, note)
SELECT sort_order, control_line, label, statement, nature, note FROM stg.tac_control_line;
GO

-- a sub code that is not a statement line stops the build here (the join drops it, the count check below finds it)
INSERT INTO dw.tac_control_member (control_line_key, line_key)
SELECT c.control_line_key, l.line_key
FROM stg.tac_control_member AS m
JOIN dw.tac_control_line AS c ON c.control_line = m.control_line
JOIN dw.tac_statutory_line AS l ON l.sub_code = m.sub_code;
GO
IF (SELECT COUNT(*) FROM dw.tac_control_member) <> (SELECT COUNT(*) FROM stg.tac_control_member)
    THROW 50000, 'authored/tac_control_line.csv: a provider line is not a line of the TAC statements', 1;
GO

INSERT INTO dw.tac_consolidated_control
    (release, printed_line, control_line_key, statement, label, amount_gbp_million, amount,
     next_report_comparative_gbp_million, source_report, pdf_page, printed_page, note)
SELECT s.release, s.printed_line, c.control_line_key, s.statement, s.label, s.amount_gbp_million,
       CAST(s.amount_gbp_million * 1000 AS decimal(19,4)), s.next_report_comparative_gbp_million, s.source_report,
       s.pdf_page, s.printed_page, s.note
FROM stg.tac_consolidated_control AS s
JOIN stg.tac_control_printed AS p ON p.printed_line = s.printed_line
JOIN dw.tac_control_line AS c ON c.control_line = p.control_line;
GO
IF (SELECT COUNT(*) FROM dw.tac_consolidated_control) <> (SELECT COUNT(*) FROM stg.tac_consolidated_control)
    THROW 50000, 'authored/tac_consolidated_control.csv: a printed line belongs to no control line', 1;
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'AUTHORED headline lines of the elimination-gap control (authored/tac_control_line.csv): labels and kinds, no amount.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'tac_control_line';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'AUTHORED membership of the control lines: which provider statement lines make up each, never a subtotal or a total. No amount.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'tac_control_member';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'AUTHORED, hand-keyed: values printed in the consolidated NHS provider accounts, with the page of each. The only authored amounts of the TAC objects; compared with the provider sum, never added to it.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'tac_consolidated_control';
GO
