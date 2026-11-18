-- dw.statement_line, dw.statement_line_member and dw.account_statement_line: the group income and expenditure statement
-- as the warehouse resolves it from authored/statement_line.csv and authored/statement_account_rule.csv.
--   dw.statement_line          one row per line of the statement, keyed by its place on the statement (line_key 1..n in
--                              sort order). A spacer gets a distinct zero-width label, because the engine treats
--                              labels that differ only in ordinary spaces as one value.
--   dw.statement_line_member   every detail line that a line adds up: a detail line adds itself, a subtotal or total
--                              adds the detail lines under its members. path_count is the number of ways the detail
--                              line is reached; it must be 1 or an amount would be counted twice (the build stops).
--   dw.account_statement_line  the detail line of each account (economic category), the winning rule and its
--                              specificity. Every account has exactly one; a build stops on an account with none or
--                              with two rules of equal specificity.
-- Authored layout, no amount. The statement ties to dw.fact_outturn because every account maps to one detail line.

DROP TABLE IF EXISTS dw.account_statement_line;
GO
DROP TABLE IF EXISTS dw.statement_line_member;
GO
DROP TABLE IF EXISTS dw.statement_line;
GO

CREATE TABLE dw.statement_line (
    line_key           int            NOT NULL CONSTRAINT pk_dw_statement_line PRIMARY KEY,
    line_id            varchar(10)    NOT NULL CONSTRAINT uq_dw_statement_line_id UNIQUE,
    label              nvarchar(100)  NOT NULL,
    label_indented     nvarchar(140)  NOT NULL,
    line_type          varchar(10)    NOT NULL,
    sign_presentation  varchar(20)    NOT NULL,
    sign_factor        smallint       NOT NULL,
    indent_level       tinyint        NOT NULL,
    sort_order         int            NOT NULL,
    plan_scope         varchar(10)    NOT NULL,
    members            varchar(200)   NOT NULL,
    detail_line_keys   varchar(400)   NOT NULL,
    evidence           nvarchar(1000) NOT NULL,
    note               nvarchar(1000) NOT NULL,
    CONSTRAINT uq_dw_statement_line_label UNIQUE (label)
);
GO

INSERT INTO dw.statement_line
    (line_key, line_id, label, label_indented, line_type, sign_presentation, sign_factor, indent_level, sort_order,
     plan_scope, members, detail_line_keys, evidence, note)
SELECT ROW_NUMBER() OVER (ORDER BY s.sort_order),
       s.line_id,
       CASE WHEN s.line_type = 'spacer'
            THEN REPLICATE(NCHAR(8203), CAST(ROW_NUMBER() OVER (PARTITION BY s.line_type ORDER BY s.sort_order) AS int))
            ELSE s.label END,
       CASE WHEN s.line_type = 'spacer'
            THEN REPLICATE(NCHAR(8203), CAST(ROW_NUMBER() OVER (PARTITION BY s.line_type ORDER BY s.sort_order) AS int))
            ELSE REPLICATE(NCHAR(160), 3 * s.indent_level) + s.label END,
       s.line_type, s.sign_presentation,
       CAST(CASE WHEN s.sign_presentation = 'income positive' THEN -1 ELSE 1 END AS smallint),
       s.indent_level, s.sort_order, s.plan_scope, s.members, '', s.evidence, s.note
FROM stg.statement_line AS s;
GO

CREATE TABLE dw.statement_line_member (
    line_key         int NOT NULL,
    detail_line_key  int NOT NULL,
    path_count       int NOT NULL,
    CONSTRAINT pk_dw_statement_line_member PRIMARY KEY (line_key, detail_line_key)
);
GO

WITH edge AS (
    SELECT l.line_key, d.line_key AS member_key
    FROM dw.statement_line AS l
    CROSS APPLY STRING_SPLIT(l.members, ' ') AS m
    JOIN dw.statement_line AS d ON d.line_id = m.value
    WHERE l.members <> '' AND m.value <> ''
), walk AS (
    SELECT l.line_key AS root, l.line_key AS cur FROM dw.statement_line AS l WHERE l.line_type <> 'spacer'
    UNION ALL
    SELECT w.root, e.member_key FROM walk AS w JOIN edge AS e ON e.line_key = w.cur
)
INSERT INTO dw.statement_line_member (line_key, detail_line_key, path_count)
SELECT w.root, w.cur, COUNT(*)
FROM walk AS w
JOIN dw.statement_line AS d ON d.line_key = w.cur AND d.line_type = 'detail'
GROUP BY w.root, w.cur;
GO

IF EXISTS (SELECT 1 FROM dw.statement_line_member WHERE path_count > 1)
    THROW 50760, 'dw.statement_line_member: a detail line is reached by two paths from one subtotal, so its amount would be added twice', 1;
IF EXISTS (SELECT 1 FROM dw.statement_line AS l
           WHERE l.line_type <> 'spacer' AND NOT EXISTS (SELECT 1 FROM dw.statement_line_member AS m WHERE m.line_key = l.line_key))
    THROW 50761, 'dw.statement_line_member: a line adds up no detail line', 1;
GO

UPDATE l
SET l.detail_line_keys = x.keys
FROM dw.statement_line AS l
JOIN (
    SELECT line_key, '|' + STRING_AGG(CAST(detail_line_key AS varchar(10)), '|') WITHIN GROUP (ORDER BY detail_line_key) + '|' AS keys
    FROM dw.statement_line_member
    GROUP BY line_key
) AS x ON x.line_key = l.line_key;
GO

CREATE TABLE dw.account_statement_line (
    account_key  int         NOT NULL CONSTRAINT pk_dw_account_statement_line PRIMARY KEY,
    line_key     int         NOT NULL,
    rule_id      varchar(20) NOT NULL,
    specificity  tinyint     NOT NULL
);
GO

WITH hit AS (
    SELECT a.account_key, r.rule_id, l.line_key, r.specificity
    FROM dw.dim_account AS a
    CROSS JOIN stg.statement_account_rule AS r
    JOIN dw.statement_line AS l ON l.line_id = r.line_id
    WHERE (r.economic_budget = '' OR EXISTS (SELECT 1 FROM STRING_SPLIT(r.economic_budget, '|') AS s WHERE s.value = a.economic_budget))
      AND (r.flow = '' OR r.flow = a.flow)
      AND (r.pesa_economic_group_code = ''
           OR EXISTS (SELECT 1 FROM STRING_SPLIT(r.pesa_economic_group_code, '|') AS s WHERE s.value = a.pesa_economic_group_code))
      AND (r.economic_category_code = ''
           OR EXISTS (SELECT 1 FROM STRING_SPLIT(r.economic_category_code, '|') AS s WHERE s.value = a.economic_category_code))
), ranked AS (
    SELECT h.*, MAX(h.specificity) OVER (PARTITION BY h.account_key) AS top_specificity FROM hit AS h
)
INSERT INTO dw.account_statement_line (account_key, line_key, rule_id, specificity)
SELECT account_key, MIN(line_key), MIN(rule_id), specificity
FROM ranked
WHERE specificity = top_specificity
GROUP BY account_key, specificity
HAVING COUNT(DISTINCT line_key) = 1;
GO

IF EXISTS (SELECT 1 FROM dw.dim_account AS a WHERE NOT EXISTS (SELECT 1 FROM dw.account_statement_line AS m WHERE m.account_key = a.account_key))
    THROW 50762, 'dw.account_statement_line: an account is selected by no rule, or by two rules of the same specificity; see sql/tests/740', 1;
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'AUTHORED layout of the group income and expenditure statement, resolved from authored/statement_line.csv. One row per statement line; no amount. A subtotal adds up the detail lines listed in dw.statement_line_member.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'statement_line';
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'AUTHORED. Every detail line a statement line adds up (a detail line adds itself). path_count is 1 everywhere, so no amount is counted twice. No amount.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'statement_line_member';
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'AUTHORED. The detail line of the statement that each account (economic category) belongs to, chosen by the most specific rule of authored/statement_account_rule.csv. Exactly one row per account; no amount.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'account_statement_line';
GO
