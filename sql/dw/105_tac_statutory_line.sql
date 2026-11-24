-- scope: full
-- dw.tac_statutory_line: one row per line of the three statements (income statement SoCI, balance sheet SoFP,
-- cash flow SoCF). The key of a line is its sub code, which is unique across the three statements (a test).
--   description       the text of the line in the latest form that carries the code (the data files have no text)
--   expected_sign     the sign the form expects for the line in that form: + (income, asset, inflow), - (expense,
--                     liability, outflow) or +/- (either). TAC amounts are as published: they are not on the OSCAR
--                     sign (spending positive); a later task chooses a presentation sign
--   section           SoFP: non-current assets, current assets, current liabilities, non-current liabilities,
--                     net assets, taxpayers' equity. SoCF: operating, investing, financing activities and the
--                     cash reconciliation. SoCI: the blocks of the statement. AUTHORED (authored/tac_line_role.csv)
--   line_kind         line | subtotal | total. A subtotal or total is computed by the form from other lines and
--                     is in the data as a value, so adding it to its components counts it twice. AUTHORED
--   form_row, table_id  where the line sits in the latest form (the income statement has two tables)
--   first_form_release, last_form_release, description_variants   the forms that carry the code
--   change_kind, change_note   from authored/tac_code_map.csv: a code retired or relabelled between years
-- Section and line_kind are the only authored columns; they never touch an amount.

DROP TABLE IF EXISTS dw.tac_fact;
GO
DROP TABLE IF EXISTS dw.tac_statutory_line;
GO

CREATE TABLE dw.tac_statutory_line (
    line_key              int            NOT NULL CONSTRAINT pk_dw_tac_statutory_line PRIMARY KEY,
    statement             varchar(4)     NOT NULL,
    sub_code              varchar(20)    NOT NULL CONSTRAINT uq_dw_tac_statutory_line_code UNIQUE,
    table_id              tinyint        NOT NULL,
    form_row              int            NOT NULL,
    description           nvarchar(400)  NOT NULL,
    expected_sign         varchar(5)     NOT NULL,
    section               nvarchar(60)   NOT NULL,
    line_kind             varchar(10)    NOT NULL,
    first_form_release    varchar(7)     NOT NULL,
    last_form_release     varchar(7)     NOT NULL,
    description_variants  int            NOT NULL,
    change_kind           varchar(20)    NULL,
    change_note           nvarchar(2000) NULL
);
GO

INSERT INTO dw.tac_statutory_line
    (line_key, statement, sub_code, table_id, form_row, description, expected_sign, section, line_kind,
     first_form_release, last_form_release, description_variants, change_kind, change_note)
SELECT ROW_NUMBER() OVER (ORDER BY CASE l.statement WHEN 'SoCI' THEN 1 WHEN 'SoFP' THEN 2 ELSE 3 END,
                                   l.table_id, l.form_row, l.sub_code),
       l.statement, l.sub_code, l.table_id, l.form_row, l.label, l.expected_sign, r.section, r.line_kind,
       a.first_release, a.last_release, a.variants, m.change_kind, m.note
FROM (SELECT t.*, ROW_NUMBER() OVER (PARTITION BY t.sub_code ORDER BY t.release DESC) AS rn
      FROM stg.tac_template_line AS t WHERE t.sub_code <> '') AS l
JOIN (SELECT sub_code, MIN(release) AS first_release, MAX(release) AS last_release,
             COUNT(DISTINCT label) AS variants
      FROM stg.tac_template_line WHERE sub_code <> '' GROUP BY sub_code) AS a ON a.sub_code = l.sub_code
JOIN stg.tac_line_role AS r ON r.sub_code = l.sub_code
LEFT JOIN stg.tac_code_map AS m ON m.old_sub_code = l.sub_code
WHERE l.rn = 1;
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'Lines of the NHS TAC income statement, balance sheet and cash flow. Text and sign from the illustrative forms (real); section and line_kind are authored (authored/tac_line_role.csv) and never touch an amount.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'tac_statutory_line';
GO
