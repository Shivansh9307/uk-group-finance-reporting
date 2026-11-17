-- Typed Estimates plan lines: one row per (workbook, sheet, row, year) of raw.plan_estimates, with
--   * the measure read from the sheet TITLE, never from the sheet name (the 2022-23 Supplementary
--     Estimate calls its excluding-depreciation sheet 'RDEL'). A title that says nothing about
--     depreciation stays 'RDEL' unless the authored plan source says the table is on the excluding-
--     depreciation basis (2026-27 Main Estimates, see authored/plan_source.csv);
--   * the unit turned into a multiplier to GBP thousands, here and not in Python;
--   * amount_k = value x multiplier, DECIMAL(19,4), GBP thousands, spending positive;
--   * is_final_plan = the single best final-plan workbook for the plan year: the Supplementary Estimate
--     if there is one, then the out-of-turn Supplementary, then the Main Estimate;
--   * the Spending Review group the cleaned line name maps to (stg.plan_name_map), and whether the
--     line is a part, a whole or a component.
-- Memo rows (o/w block grant adjustments, o/w depreciation) are kept with row_kind = 'memo' and are never
-- added into anything.

DROP TABLE IF EXISTS stg.plan_estimates_line;
GO

CREATE TABLE stg.plan_estimates_line (
    file_id            int            NOT NULL,
    edition            varchar(30)    NOT NULL,   -- 2023-24-supps
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
    unit_multiplier    int            NULL,       -- GBP thousands per published unit; NULL = unit not recognised
    measure_from_title varchar(40)    NOT NULL,
    measure            varchar(40)    NOT NULL,   -- after the authored basis override
    basis_overridden   bit            NOT NULL,
    value_published    decimal(38,18) NULL,
    amount_k           decimal(19,4)  NULL,
    is_final_plan      bit            NOT NULL,
    target_type        varchar(30)    NULL,
    target_name        nvarchar(400)  NULL,
    line_role          varchar(20)    NULL,
    CONSTRAINT pk_stg_plan_estimates_line PRIMARY KEY (file_id, sheet, source_row, year_label)
);
GO

WITH base AS (
    SELECT
        r.file_id, f.edition, 'EST_' + REPLACE(UPPER(f.edition), '-', '_') AS plan_source_code,
        r.sheet, r.source_row, r.year_label, r.status_label, r.section, r.row_label_clean, r.row_kind,
        r.table_title, r.unit, r.value_published,
        CASE WHEN LOWER(r.unit) LIKE '%billion%' THEN 1000000
             WHEN LOWER(r.unit) LIKE '%million%' THEN 1000
             WHEN LOWER(r.unit) LIKE '%thousand%' THEN 1 END AS unit_multiplier,
        CASE WHEN LOWER(r.table_title) LIKE '%tax changes%' THEN 'RDEL_EX_DEPN_TAX_ALLOWANCE'
             WHEN LOWER(r.table_title) LIKE '%excluding depreciation%' THEN 'RDEL_EX_DEPN'
             WHEN LOWER(r.table_title) LIKE '%resource%' THEN 'RDEL'
             WHEN LOWER(r.table_title) LIKE '%capital%' THEN 'CDEL'
             ELSE 'UNKNOWN' END AS measure_from_title,
        -- release suffix rank: Supplementary first, then out-of-turn Supplementary, then Main
        CASE WHEN f.edition LIKE '%-oot-supps' THEN 2 WHEN f.edition LIKE '%-supps' THEN 1 ELSE 3 END AS edition_rank
    FROM raw.plan_estimates AS r
    JOIN raw.plan_source_file AS f ON f.file_id = r.file_id
),
best AS (
    -- one workbook per plan year: lowest rank among the workbooks that carry a 'plans' column for that year
    SELECT year_label, MIN(edition_rank) AS best_rank
    FROM base
    WHERE status_label = 'plans'
    GROUP BY year_label
)
INSERT INTO stg.plan_estimates_line
    (file_id, edition, plan_source_code, sheet, source_row, year_label, status_label, section, row_label_clean,
     row_kind, table_title, unit, unit_multiplier, measure_from_title, measure, basis_overridden,
     value_published, amount_k, is_final_plan, target_type, target_name, line_role)
SELECT
    b.file_id, b.edition, b.plan_source_code, b.sheet, b.source_row, b.year_label, b.status_label, b.section,
    b.row_label_clean, b.row_kind, b.table_title, b.unit, b.unit_multiplier, b.measure_from_title,
    CASE WHEN b.measure_from_title = 'RDEL' AND ps.resource_basis = 'ex_depreciation' THEN 'RDEL_EX_DEPN'
         ELSE b.measure_from_title END,
    CAST(CASE WHEN b.measure_from_title = 'RDEL' AND ps.resource_basis = 'ex_depreciation' THEN 1 ELSE 0 END AS bit),
    b.value_published,
    CAST(b.value_published * b.unit_multiplier AS decimal(19,4)),
    CAST(CASE WHEN b.status_label = 'plans' AND b.edition_rank = best.best_rank THEN 1 ELSE 0 END AS bit),
    m.target_type, m.target_name, m.line_role
FROM base AS b
LEFT JOIN best ON best.year_label = b.year_label
LEFT JOIN stg.plan_source AS ps ON ps.plan_source_code = b.plan_source_code
LEFT JOIN stg.plan_name_map AS m ON m.name_family = 'hmt_tables' AND m.plan_name = b.row_label_clean;
GO
