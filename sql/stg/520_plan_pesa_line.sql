-- Typed PESA and Spending Review 2025 lines: one row per cell of a department-group table.
--   A "group table" section is one whose lines are departmental groups (Resource DEL by departmental group,
--   Administration budgets, Capital DEL by departmental group ...). The rules below are the ones the
--   profiling used (ukfr.profile.plans), written again here in T-SQL; a Python test compares the two.
--   Only nominal tables are kept: tables in real terms are left out. Total managed expenditure sections
--   are left out too (they hold debt interest, accounting adjustments and other lines that are not plans).
--   measure:
--     RDEL, RDEL_EX_DEPN, CDEL, TDEL        departmental expenditure limits
--     RESOURCE_DEPT_AME, CAPITAL_DEPT_AME   departmental annually managed expenditure
--     ADMIN, ADMIN_EX_DEPN                  administration budgets (a part of resource DEL)
--   A table that is not titled 'excluding depreciation' but sits on that basis is overridden through the
--   authored plan source (PESA 2026), so its ADMIN becomes ADMIN_EX_DEPN.
--   amount_k = value x unit multiplier, DECIMAL(19,4), GBP thousands.

DROP TABLE IF EXISTS stg.plan_pesa_line;
GO

CREATE TABLE stg.plan_pesa_line (
    file_id            int            NOT NULL,
    edition            varchar(30)    NOT NULL,   -- 2022, 2023, 2024, 2025-07, 2025-12, 2026, sr2025
    plan_source_code   varchar(40)    NOT NULL,
    sheet              nvarchar(100)  NOT NULL,
    source_row         int            NOT NULL,
    year_label         varchar(7)     NOT NULL,
    status_label       varchar(20)    NOT NULL,
    section            nvarchar(400)  NOT NULL,
    row_label_clean    nvarchar(400)  NOT NULL,
    row_kind           varchar(10)    NOT NULL,
    table_title        nvarchar(400)  NOT NULL,
    unit               nvarchar(100)  NOT NULL,
    unit_multiplier    int            NULL,
    measure_from_title varchar(40)    NOT NULL,
    measure            varchar(40)    NOT NULL,
    basis_overridden   bit            NOT NULL,
    value_published    decimal(38,18) NULL,
    amount_k           decimal(19,4)  NULL,
    target_type        varchar(30)    NULL,
    target_name        nvarchar(400)  NULL,
    line_role          varchar(20)    NULL,
    CONSTRAINT pk_stg_plan_pesa_line PRIMARY KEY (file_id, sheet, source_row, year_label)
);
GO

WITH t AS (
    SELECT r.*, f.edition,
           LOWER(r.table_title) AS t, LOWER(r.section) AS s
    FROM raw.plan_pesa AS r
    JOIN raw.plan_source_file AS f ON f.file_id = r.file_id
),
g AS (
    SELECT t.*,
        CASE WHEN t.s LIKE '%by departmental group%'
               OR t.t LIKE '%administration budgets%'
               OR (t.section = '' AND (t.t LIKE '%departmental expenditure limits%' OR t.t LIKE '%(del)%'))
             THEN 1 ELSE 0 END AS is_group_section,
        CASE WHEN t.t LIKE '%real terms%' THEN 1 ELSE 0 END AS is_real_terms
    FROM t
),
m AS (
    SELECT g.*,
        CASE
            WHEN g.is_group_section = 0 THEN ''
            WHEN g.t LIKE '%administration%' THEN CASE WHEN g.t LIKE '%excluding depreciation%' THEN 'ADMIN_EX_DEPN' ELSE 'ADMIN' END
            WHEN g.s LIKE '%resource departmental ame%' OR g.s LIKE '%resource ame%' THEN 'RESOURCE_DEPT_AME'
            WHEN g.s LIKE '%capital departmental ame%' OR g.s LIKE '%capital ame%' THEN 'CAPITAL_DEPT_AME'
            WHEN (g.s LIKE '%excluding depreciation%' OR g.t LIKE '%excluding depreciation%')
                 AND (g.s LIKE '%resource%' OR g.t LIKE '%resource%') THEN 'RDEL_EX_DEPN'
            WHEN g.s LIKE '%resource del%' OR (g.t LIKE '%resource%' AND g.s LIKE '%del%') THEN 'RDEL'
            WHEN g.s LIKE '%capital del%' OR g.t LIKE '%capital departmental expenditure limits%' OR g.t LIKE '%capital del%' THEN 'CDEL'
            WHEN g.s LIKE '%total del%' OR REPLACE(g.t, '(del)', '') LIKE '%total departmental expenditure limits%' THEN 'TDEL'
            ELSE '' END AS measure_from_title
    FROM g
)
INSERT INTO stg.plan_pesa_line
    (file_id, edition, plan_source_code, sheet, source_row, year_label, status_label, section, row_label_clean,
     row_kind, table_title, unit, unit_multiplier, measure_from_title, measure, basis_overridden,
     value_published, amount_k, target_type, target_name, line_role)
SELECT
    m.file_id, m.edition,
    CASE WHEN m.edition = 'sr2025' THEN 'SR25' ELSE 'PESA_' + REPLACE(UPPER(m.edition), '-', '_') END,
    m.sheet, m.source_row, m.year_label, m.status_label, m.section, m.row_label_clean, m.row_kind,
    m.table_title, m.unit,
    CASE WHEN LOWER(m.unit) LIKE '%billion%' THEN 1000000
         WHEN LOWER(m.unit) LIKE '%million%' THEN 1000
         WHEN LOWER(m.unit) LIKE '%thousand%' THEN 1 END,
    m.measure_from_title,
    CASE WHEN m.measure_from_title = 'ADMIN' AND ps.resource_basis = 'ex_depreciation' THEN 'ADMIN_EX_DEPN'
         ELSE m.measure_from_title END,
    CAST(CASE WHEN m.measure_from_title = 'ADMIN' AND ps.resource_basis = 'ex_depreciation' THEN 1 ELSE 0 END AS bit),
    m.value_published,
    CAST(m.value_published * CASE WHEN LOWER(m.unit) LIKE '%billion%' THEN 1000000
                                  WHEN LOWER(m.unit) LIKE '%million%' THEN 1000
                                  WHEN LOWER(m.unit) LIKE '%thousand%' THEN 1 END AS decimal(19,4)),
    mp.target_type, mp.target_name, mp.line_role
FROM m
LEFT JOIN stg.plan_source AS ps
       ON ps.plan_source_code = CASE WHEN m.edition = 'sr2025' THEN 'SR25' ELSE 'PESA_' + REPLACE(UPPER(m.edition), '-', '_') END
LEFT JOIN stg.plan_name_map AS mp ON mp.name_family = 'hmt_tables' AND mp.plan_name = m.row_label_clean
WHERE m.measure_from_title <> '' AND m.is_real_terms = 0
  AND m.row_kind IN ('line', 'total');
GO
