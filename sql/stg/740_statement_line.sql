-- stg.statement_line and stg.statement_account_rule: typed copies of authored/statement_line.csv and
-- authored/statement_account_rule.csv (read from authored.statement_line and authored.statement_account_rule).
-- Together they are the layout of the group income and expenditure statement.
--   statement_line          one row per line of the statement: its label, order, type (detail | subtotal | total |
--                           spacer), the sign it is presented in (as reported | income positive), its indent, the
--                           list of lines it adds up (a subtotal or a total) and, for the lines that sit at a
--                           published plan's grain, the plan scope (RESOURCE | CAPITAL | ALL).
--   statement_account_rule  how an account (an economic category) reaches a detail line. A rule leaves a field
--                           blank to mean any value, and a field may list values separated by | . Where several
--                           rules select one account the most specific wins: a category rule beats a group rule
--                           (4), which beats a flow rule (2), which beats an economic budget rule (1).
-- The build stops here, with a message, when the files break a rule. They hold no amount; they decide which line of
-- the statement a real amount is added to.

DROP TABLE IF EXISTS stg.statement_account_rule;
GO
DROP TABLE IF EXISTS stg.statement_line;
GO

CREATE TABLE stg.statement_line (
    line_id            varchar(10)    NOT NULL CONSTRAINT pk_stg_statement_line PRIMARY KEY,
    label              nvarchar(100)  NOT NULL,
    sort_order         int            NOT NULL,
    line_type          varchar(10)    NOT NULL,
    sign_presentation  varchar(20)    NOT NULL,
    indent_level       tinyint        NOT NULL,
    members            varchar(200)   NOT NULL,
    plan_scope         varchar(10)    NOT NULL,
    evidence           nvarchar(1000) NOT NULL,
    note               nvarchar(1000) NOT NULL,
    load_order         int            NOT NULL
);
GO

CREATE TABLE stg.statement_account_rule (
    rule_id                   varchar(20)    NOT NULL CONSTRAINT pk_stg_statement_account_rule PRIMARY KEY,
    line_id                   varchar(10)    NOT NULL,
    economic_budget           nvarchar(200)  NOT NULL,
    flow                      varchar(20)    NOT NULL,
    pesa_economic_group_code  nvarchar(1000) NOT NULL,
    economic_category_code    nvarchar(1000) NOT NULL,
    specificity               tinyint        NOT NULL,
    evidence                  nvarchar(1000) NOT NULL,
    note                      nvarchar(1000) NOT NULL,
    load_order                int            NOT NULL
);
GO

INSERT INTO stg.statement_line
    (line_id, label, sort_order, line_type, sign_presentation, indent_level, members, plan_scope, evidence, note, load_order)
SELECT LTRIM(RTRIM(line_id)), LTRIM(RTRIM(label)), CAST(LTRIM(RTRIM(sort_order)) AS int), LTRIM(RTRIM(line_type)),
       LTRIM(RTRIM(sign_presentation)), CAST(LTRIM(RTRIM(indent_level)) AS tinyint), LTRIM(RTRIM(members)),
       LTRIM(RTRIM(plan_scope)), evidence, note, _load_order
FROM authored.statement_line;
GO

INSERT INTO stg.statement_account_rule
    (rule_id, line_id, economic_budget, flow, pesa_economic_group_code, economic_category_code, specificity,
     evidence, note, load_order)
SELECT LTRIM(RTRIM(rule_id)), LTRIM(RTRIM(line_id)), LTRIM(RTRIM(economic_budget)), LTRIM(RTRIM(flow)),
       LTRIM(RTRIM(pesa_economic_group_code)), LTRIM(RTRIM(economic_category_code)),
       CAST((CASE WHEN LTRIM(RTRIM(economic_budget)) <> '' THEN 1 ELSE 0 END)
          + (CASE WHEN LTRIM(RTRIM(flow)) <> '' THEN 2 ELSE 0 END)
          + (CASE WHEN LTRIM(RTRIM(pesa_economic_group_code)) <> '' THEN 4 ELSE 0 END)
          + (CASE WHEN LTRIM(RTRIM(economic_category_code)) <> '' THEN 8 ELSE 0 END) AS tinyint),
       evidence, note, _load_order
FROM authored.statement_account_rule;
GO

-- the layout
IF EXISTS (SELECT 1 FROM stg.statement_line WHERE evidence = '' OR note = '')
    THROW 50740, 'authored/statement_line.csv: every row needs evidence and a note', 1;
IF EXISTS (SELECT 1 FROM stg.statement_line WHERE line_type NOT IN ('detail', 'subtotal', 'total', 'spacer'))
    THROW 50741, 'authored/statement_line.csv: line_type must be detail, subtotal, total or spacer', 1;
IF EXISTS (SELECT 1 FROM stg.statement_line WHERE sign_presentation NOT IN ('as reported', 'income positive'))
    THROW 50742, 'authored/statement_line.csv: sign_presentation must be as reported or income positive', 1;
IF EXISTS (SELECT 1 FROM stg.statement_line WHERE plan_scope NOT IN ('', 'RESOURCE', 'CAPITAL', 'ALL'))
    THROW 50743, 'authored/statement_line.csv: plan_scope must be blank, RESOURCE, CAPITAL or ALL', 1;
IF EXISTS (SELECT 1 FROM stg.statement_line GROUP BY sort_order HAVING COUNT(*) > 1)
    THROW 50744, 'authored/statement_line.csv: two lines have the same sort_order', 1;
IF EXISTS (SELECT 1 FROM stg.statement_line WHERE line_type = 'spacer' AND label <> '')
    THROW 50745, 'authored/statement_line.csv: a spacer has no label (the build writes a distinct zero-width label)', 1;
IF EXISTS (SELECT 1 FROM stg.statement_line WHERE line_type <> 'spacer' AND label = '')
    THROW 50746, 'authored/statement_line.csv: only a spacer has no label', 1;
IF EXISTS (SELECT 1 FROM stg.statement_line GROUP BY label HAVING label <> '' AND COUNT(*) > 1)
    THROW 50747, 'authored/statement_line.csv: two lines have the same label', 1;
IF EXISTS (SELECT 1 FROM stg.statement_line WHERE line_type IN ('subtotal', 'total') AND members = '')
    THROW 50748, 'authored/statement_line.csv: a subtotal or total lists the lines it adds up', 1;
IF EXISTS (SELECT 1 FROM stg.statement_line WHERE line_type IN ('detail', 'spacer') AND members <> '')
    THROW 50749, 'authored/statement_line.csv: only a subtotal or total has members', 1;
IF EXISTS (SELECT 1 FROM stg.statement_line WHERE plan_scope <> '' AND line_type NOT IN ('subtotal', 'total'))
    THROW 50750, 'authored/statement_line.csv: a plan scope belongs to a subtotal or total', 1;
-- members must exist, must not be a spacer, must come earlier on the statement (so no line can add itself, directly or
-- through another line) and must not be listed twice
IF EXISTS (
    SELECT 1
    FROM stg.statement_line AS l
    CROSS APPLY STRING_SPLIT(l.members, ' ') AS m
    WHERE l.members <> '' AND m.value <> ''
      AND NOT EXISTS (SELECT 1 FROM stg.statement_line AS x
                      WHERE x.line_id = m.value AND x.line_type <> 'spacer' AND x.sort_order < l.sort_order)
)
    THROW 50751, 'authored/statement_line.csv: a member is not a line, is a spacer, or does not come before the line that adds it up', 1;
IF EXISTS (
    SELECT 1
    FROM stg.statement_line AS l
    CROSS APPLY STRING_SPLIT(l.members, ' ') AS m
    WHERE l.members <> '' AND m.value <> ''
    GROUP BY l.line_id, m.value HAVING COUNT(*) > 1
)
    THROW 50752, 'authored/statement_line.csv: a line lists the same member twice', 1;

-- the rules
IF EXISTS (SELECT 1 FROM stg.statement_account_rule WHERE evidence = '' OR note = '')
    THROW 50753, 'authored/statement_account_rule.csv: every row needs evidence and a note', 1;
IF EXISTS (SELECT 1 FROM stg.statement_account_rule AS r
           WHERE NOT EXISTS (SELECT 1 FROM stg.statement_line AS l WHERE l.line_id = r.line_id AND l.line_type = 'detail'))
    THROW 50754, 'authored/statement_account_rule.csv: a rule points at a line that is not a detail line of statement_line.csv', 1;
IF EXISTS (SELECT 1 FROM stg.statement_line AS l
           WHERE l.line_type = 'detail' AND NOT EXISTS (SELECT 1 FROM stg.statement_account_rule AS r WHERE r.line_id = l.line_id))
    THROW 50755, 'authored/statement_line.csv: a detail line has no rule', 1;
IF EXISTS (SELECT 1 FROM stg.statement_account_rule WHERE flow NOT IN ('', 'Expenditure', 'Income', 'Not applicable'))
    THROW 50756, 'authored/statement_account_rule.csv: flow must be blank, Expenditure, Income or Not applicable', 1;
IF EXISTS (SELECT 1 FROM stg.statement_account_rule WHERE specificity = 0)
    THROW 50757, 'authored/statement_account_rule.csv: a rule with every field blank would select every account', 1;
GO
