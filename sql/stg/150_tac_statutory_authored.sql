-- scope: full
-- stg.tac_cash_flow_line, stg.tac_cash_flow_map, stg.tac_control_line, stg.tac_control_member, stg.tac_control_printed,
-- stg.tac_consolidated_control: typed copies of the four authored files that the cash-flow derivation and the
-- elimination-gap control read.
--   authored/tac_cash_flow_line.csv         the lines of the derived (indirect) cash flow and their sections
--   authored/tac_cash_flow_map.csv          which statement line feeds which derived line, with what factor; and which
--                                           derived line each published cash-flow line is compared with
--   authored/tac_control_line.csv           the six headline lines of the elimination-gap control, with the provider
--                                           lines and the printed consolidated lines each is made of
--   authored/tac_consolidated_control.csv   the values keyed from the printed consolidated statements (GBP million),
--                                           with the page of each
-- The control values are the only authored amounts in the TAC objects; they are never added to a provider amount (a
-- test says so). The build stops, with a message, when a file breaks a rule. Whether a sub code exists and whether
-- a derived line is used is checked by the tests of sql/tests/150 onwards, after the warehouse tables exist.

DROP TABLE IF EXISTS stg.tac_consolidated_control;
GO
DROP TABLE IF EXISTS stg.tac_control_printed;
GO
DROP TABLE IF EXISTS stg.tac_control_member;
GO
DROP TABLE IF EXISTS stg.tac_control_line;
GO
DROP TABLE IF EXISTS stg.tac_cash_flow_map;
GO
DROP TABLE IF EXISTS stg.tac_cash_flow_line;
GO

CREATE TABLE stg.tac_cash_flow_line (
    line_code   varchar(20)    NOT NULL CONSTRAINT pk_stg_tac_cash_flow_line PRIMARY KEY,
    label       nvarchar(200)  NOT NULL,
    section     nvarchar(60)   NOT NULL,
    sort_order  int            NOT NULL CONSTRAINT uq_stg_tac_cash_flow_line_sort UNIQUE,
    line_kind   varchar(20)    NOT NULL,
    note        nvarchar(1000) NOT NULL
);
GO
CREATE TABLE stg.tac_cash_flow_map (
    sub_code      varchar(20)    NOT NULL,
    statement     varchar(4)     NOT NULL,
    treatment     varchar(10)    NOT NULL,
    basis         varchar(10)    NULL,
    factor        int            NULL,
    derived_line  varchar(20)    NULL,
    note          nvarchar(1000) NOT NULL,
    load_order    int            NOT NULL CONSTRAINT pk_stg_tac_cash_flow_map PRIMARY KEY
);
GO
CREATE TABLE stg.tac_control_line (
    control_line  varchar(30)    NOT NULL CONSTRAINT pk_stg_tac_control_line PRIMARY KEY,
    label         nvarchar(100)  NOT NULL,
    statement     varchar(4)     NOT NULL,
    nature        varchar(10)    NOT NULL,
    sort_order    int            NOT NULL,
    note          nvarchar(1000) NOT NULL
);
GO
CREATE TABLE stg.tac_control_member (
    control_line  varchar(30)    NOT NULL,
    sub_code      varchar(20)    NOT NULL,
    CONSTRAINT pk_stg_tac_control_member PRIMARY KEY (control_line, sub_code)
);
GO
CREATE TABLE stg.tac_control_printed (
    control_line  varchar(30)    NOT NULL,
    printed_line  varchar(40)    NOT NULL CONSTRAINT pk_stg_tac_control_printed PRIMARY KEY
);
GO
CREATE TABLE stg.tac_consolidated_control (
    release                              varchar(7)     NOT NULL,
    statement                            varchar(4)     NOT NULL,
    printed_line                         varchar(40)    NOT NULL,
    label                                nvarchar(100)  NOT NULL,
    amount_gbp_million                   decimal(19,4)  NOT NULL,
    next_report_comparative_gbp_million  decimal(19,4)  NULL,
    source_report                        nvarchar(200)  NOT NULL,
    pdf_page                             int            NOT NULL,
    printed_page                         int            NOT NULL,
    note                                 nvarchar(1000) NOT NULL,
    CONSTRAINT pk_stg_tac_consolidated_control PRIMARY KEY (release, printed_line)
);
GO

IF EXISTS (SELECT 1 FROM authored.tac_cash_flow_line WHERE TRY_CAST(sort_order AS int) IS NULL)
    THROW 50000, 'authored/tac_cash_flow_line.csv: sort_order is not a whole number', 1;
IF EXISTS (SELECT 1 FROM authored.tac_cash_flow_map WHERE NULLIF(LTRIM(RTRIM(factor)), '') IS NOT NULL AND TRY_CAST(factor AS int) IS NULL)
    THROW 50000, 'authored/tac_cash_flow_map.csv: factor is not a whole number', 1;
IF EXISTS (SELECT 1 FROM authored.tac_control_line WHERE NULLIF(LTRIM(RTRIM(tac_lines)), '') IS NULL OR NULLIF(LTRIM(RTRIM(printed_lines)), '') IS NULL)
    THROW 50000, 'authored/tac_control_line.csv: every control line needs provider lines and printed lines', 1;
IF EXISTS (SELECT 1 FROM authored.tac_consolidated_control
           WHERE TRY_CAST(amount_gbp_million AS decimal(19,4)) IS NULL
              OR (NULLIF(LTRIM(RTRIM(next_report_comparative_gbp_million)), '') IS NOT NULL
                  AND TRY_CAST(next_report_comparative_gbp_million AS decimal(19,4)) IS NULL)
              OR TRY_CAST(pdf_page AS int) IS NULL OR TRY_CAST(printed_page AS int) IS NULL)
    THROW 50000, 'authored/tac_consolidated_control.csv: an amount or a page is not a number', 1;
GO

INSERT INTO stg.tac_cash_flow_line (line_code, label, section, sort_order, line_kind, note)
SELECT LTRIM(RTRIM(line_code)), LTRIM(RTRIM(label)), LTRIM(RTRIM(section)), CAST(sort_order AS int),
       LTRIM(RTRIM(kind)), note
FROM authored.tac_cash_flow_line;
GO
INSERT INTO stg.tac_cash_flow_map (sub_code, statement, treatment, basis, factor, derived_line, note, load_order)
SELECT LTRIM(RTRIM(sub_code)), LTRIM(RTRIM(statement)), LTRIM(RTRIM(treatment)), NULLIF(LTRIM(RTRIM(basis)), ''),
       TRY_CAST(NULLIF(LTRIM(RTRIM(factor)), '') AS int), NULLIF(LTRIM(RTRIM(derived_line)), ''), note, _load_order
FROM authored.tac_cash_flow_map;
GO
INSERT INTO stg.tac_control_line (control_line, label, statement, nature, sort_order, note)
SELECT LTRIM(RTRIM(control_line)), LTRIM(RTRIM(label)), LTRIM(RTRIM(statement)), LTRIM(RTRIM(nature)), _load_order, note
FROM authored.tac_control_line;
GO
INSERT INTO stg.tac_control_member (control_line, sub_code)
SELECT LTRIM(RTRIM(c.control_line)), LTRIM(RTRIM(s.value))
FROM authored.tac_control_line AS c
CROSS APPLY STRING_SPLIT(c.tac_lines, ';') AS s
WHERE LTRIM(RTRIM(s.value)) <> '';
GO
INSERT INTO stg.tac_control_printed (control_line, printed_line)
SELECT LTRIM(RTRIM(c.control_line)), LTRIM(RTRIM(s.value))
FROM authored.tac_control_line AS c
CROSS APPLY STRING_SPLIT(c.printed_lines, ';') AS s
WHERE LTRIM(RTRIM(s.value)) <> '';
GO
INSERT INTO stg.tac_consolidated_control
    (release, statement, printed_line, label, amount_gbp_million, next_report_comparative_gbp_million, source_report,
     pdf_page, printed_page, note)
SELECT LTRIM(RTRIM(release)), LTRIM(RTRIM(statement)), LTRIM(RTRIM(printed_line)), LTRIM(RTRIM(label)),
       CAST(amount_gbp_million AS decimal(19,4)),
       TRY_CAST(NULLIF(LTRIM(RTRIM(next_report_comparative_gbp_million)), '') AS decimal(19,4)),
       source_report, CAST(pdf_page AS int), CAST(printed_page AS int), note
FROM authored.tac_consolidated_control;
GO

IF EXISTS (SELECT 1 FROM stg.tac_cash_flow_line WHERE line_kind NOT IN ('compared', 'derived_only', 'published_only'))
    THROW 50000, 'authored/tac_cash_flow_line.csv: kind must be compared, derived_only or published_only', 1;
IF EXISTS (SELECT 1 FROM stg.tac_cash_flow_map WHERE treatment NOT IN ('derive', 'compare', 'result', 'not_used')
                                                 OR statement NOT IN ('SoCI', 'SoFP', 'SoCF'))
    THROW 50000, 'authored/tac_cash_flow_map.csv: treatment must be derive, compare, result or not_used and statement SoCI, SoFP or SoCF', 1;
IF EXISTS (SELECT 1 FROM stg.tac_cash_flow_map
           WHERE (treatment = 'derive' AND (basis NOT IN ('movement', 'flow') OR factor NOT IN (-1, 1) OR derived_line IS NULL))
              OR (treatment = 'compare' AND (basis <> 'published' OR factor <> 1 OR derived_line IS NULL))
              OR (treatment IN ('result', 'not_used') AND (basis IS NOT NULL OR factor IS NOT NULL OR derived_line IS NOT NULL)))
    THROW 50000, 'authored/tac_cash_flow_map.csv: a row does not follow the columns its treatment needs', 1;
IF EXISTS (SELECT 1 FROM stg.tac_cash_flow_map WHERE derived_line IS NOT NULL
                                                 AND derived_line NOT IN (SELECT line_code FROM stg.tac_cash_flow_line))
    THROW 50000, 'authored/tac_cash_flow_map.csv: a derived line is not in authored/tac_cash_flow_line.csv', 1;
IF EXISTS (SELECT 1 FROM stg.tac_control_line WHERE nature NOT IN ('flow', 'balance') OR statement NOT IN ('SoCI', 'SoFP'))
    THROW 50000, 'authored/tac_control_line.csv: nature must be flow or balance and statement SoCI or SoFP', 1;
IF EXISTS (SELECT 1 FROM stg.tac_control_printed AS p
           WHERE p.printed_line NOT IN (SELECT printed_line FROM stg.tac_consolidated_control))
    THROW 50000, 'authored/tac_control_line.csv: a printed line is not in authored/tac_consolidated_control.csv', 1;
GO
