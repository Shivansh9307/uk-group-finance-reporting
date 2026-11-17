-- dw.fact_plan: spending plans, real published numbers only, at four grains (grain_code).
--   A  OSCAR Plans (FY2017-18 to FY2021-22): financial year x organisation x control budget detail x
--      economic budget. Needs the annual extracts, so it is added by dw/525 in a full-scope build only.
--   B  Estimates, FY2023-24 to FY2026-27: financial year x Spending Review group x measure, from the one
--      final-plan workbook per year (Supplementary Estimate where it exists, Main Estimate for FY2026-27).
--      Measures: resource DEL excluding depreciation (RDEL_EX_DEPN) and capital DEL (CDEL).
--   C  Estimates, FY2022-23: the same lines, but the three departments reorganised in February 2023
--      (BEIS, DCMS, DIT) sit in one combined group, so a group-level plan-to-outturn comparison is only
--      valid at that combined group and at total DEL.
--   D  PESA departmental AME and administration budgets by Spending Review group, one row per plan year from
--      the latest edition that still calls the year 'plans'.
-- Lines that are not departments (reserves, OBR allowance, Budget Exchange adjustment, unallocated funds) and
-- the Single Intelligence Account are kept, so that the sum of a year and measure equals the published total.
-- Lines flagged component in stg.plan_name_map are part of another line and are never added.
-- Lines flagged 'part' (Transport and High Speed 2, Energy Security and Net Zero and Sizewell C) are added
-- into one row per group.
-- amount: GBP thousands, DECIMAL(19,4), spending positive; every unit conversion happened in stg.
-- is_part_of_other_measure = 1 for administration budgets, which are a part of resource DEL: do not add them to it.

DROP TABLE IF EXISTS dw.plan_coverage;
DROP TABLE IF EXISTS dw.fact_plan;
DROP TABLE IF EXISTS dw.dim_plan_grain;
GO

CREATE TABLE dw.dim_plan_grain (
    grain_code   char(1)        NOT NULL CONSTRAINT pk_dw_dim_plan_grain PRIMARY KEY,
    grain_name   varchar(40)    NOT NULL,
    description  nvarchar(600)  NOT NULL
);
GO

INSERT INTO dw.dim_plan_grain (grain_code, grain_name, description) VALUES
 ('A', 'OSCAR organisation',  N'OSCAR Plans: financial year x organisation x control budget detail x economic budget. Finer allocation (economic category, sub-segment) is not comparable with outturn.'),
 ('B', 'Estimates group',     N'Estimates, FY2023-24 to FY2026-27: financial year x Spending Review group x measure (resource DEL excluding depreciation, capital DEL).'),
 ('C', 'Estimates 2022-23',   N'Estimates, FY2022-23: group lines as published; BEIS, DCMS and DIT are one combined group, so only the combined group and total DEL are comparable with outturn.'),
 ('D', 'PESA group',          N'PESA departmental AME and administration budgets by Spending Review group, to 2028-29.');
GO

CREATE TABLE dw.fact_plan (
    plan_fact_key             int            NOT NULL CONSTRAINT pk_dw_fact_plan PRIMARY KEY,
    plan_source_key           int            NOT NULL,
    financial_year            varchar(7)     NOT NULL,
    sr_group_key              int            NOT NULL,
    organisation_code         nvarchar(50)   NULL,        -- NULL where the grain has no organisation (B, C, D)
    control_budget_detail     varchar(30)    NOT NULL,    -- DEL PROG | DEL ADMIN | DEPT AME | NON-DEPT AME | NON-BUDGET (OSCAR); DEL (Estimates, programme and administration together)
    economic_budget           varchar(20)    NOT NULL,    -- RESOURCE | CAPITAL | n/a
    measure                   varchar(40)    NOT NULL,    -- RDEL (incl. depreciation, OSCAR), RDEL_EX_DEPN, CDEL, RAME, CAME, ADMIN, ADMIN_EX_DEPN, NON_DEPT_AME, NON_BUDGET
    amount                    decimal(19,4)  NOT NULL,    -- GBP thousands
    grain_code                char(1)        NOT NULL,
    source_line_count         int            NOT NULL,    -- published lines or extract rows added into this row
    is_part_of_other_measure  bit            NOT NULL,
    CONSTRAINT fk_dw_fact_plan_source FOREIGN KEY (plan_source_key) REFERENCES dw.dim_plan_source (plan_source_key),
    CONSTRAINT fk_dw_fact_plan_group  FOREIGN KEY (sr_group_key)    REFERENCES dw.dim_sr_group (sr_group_key),
    CONSTRAINT fk_dw_fact_plan_grain  FOREIGN KEY (grain_code)      REFERENCES dw.dim_plan_grain (grain_code)
);
GO

WITH estimates AS (
    SELECT
        CASE WHEN l.year_label = '2022-23' THEN 'C' ELSE 'B' END AS grain_code,
        ps.plan_source_key, l.year_label AS financial_year, g.sr_group_key,
        CAST(NULL AS nvarchar(50)) AS organisation_code,
        CAST('DEL' AS varchar(30)) AS control_budget_detail,
        CAST(CASE l.measure WHEN 'CDEL' THEN 'CAPITAL' ELSE 'RESOURCE' END AS varchar(20)) AS economic_budget,
        l.measure,
        SUM(l.amount_k) AS amount, COUNT(*) AS source_line_count, CAST(0 AS bit) AS is_part_of_other_measure
    FROM stg.plan_estimates_line AS l
    JOIN dw.dim_sr_group AS g ON g.sr_group_name = l.target_name
    JOIN dw.dim_plan_source AS ps ON ps.plan_source_code = l.plan_source_code
    WHERE l.is_final_plan = 1 AND l.row_kind = 'line' AND l.line_role <> 'component'
      AND l.measure IN ('RDEL_EX_DEPN', 'CDEL') AND l.amount_k IS NOT NULL
    GROUP BY CASE WHEN l.year_label = '2022-23' THEN 'C' ELSE 'B' END, ps.plan_source_key, l.year_label,
             g.sr_group_key, l.measure
),
pesa_lines AS (
    SELECT l.*, ps.edition_seq,
           CASE l.measure WHEN 'RESOURCE_DEPT_AME' THEN 'RAME' WHEN 'CAPITAL_DEPT_AME' THEN 'CAME' ELSE l.measure END AS fact_measure
    FROM stg.plan_pesa_line AS l
    JOIN stg.plan_source AS ps ON ps.plan_source_code = l.plan_source_code
    WHERE l.row_kind = 'line' AND l.status_label = 'plans' AND l.amount_k IS NOT NULL
      AND l.measure IN ('RESOURCE_DEPT_AME', 'CAPITAL_DEPT_AME', 'ADMIN', 'ADMIN_EX_DEPN')
      AND l.edition <> 'sr2025'
),
pesa_best AS (
    -- the latest edition that still calls the year 'plans', per year and kind of budget (resource AME, capital AME,
    -- administration with or without depreciation, so a year never gets two administration plans on different bases)
    SELECT year_label,
           CASE WHEN fact_measure IN ('ADMIN', 'ADMIN_EX_DEPN') THEN 'ADMIN' ELSE fact_measure END AS budget_kind,
           MAX(edition_seq) AS best_seq
    FROM pesa_lines
    GROUP BY year_label, CASE WHEN fact_measure IN ('ADMIN', 'ADMIN_EX_DEPN') THEN 'ADMIN' ELSE fact_measure END
),
pesa AS (
    SELECT
        'D' AS grain_code, ps.plan_source_key, l.year_label AS financial_year, g.sr_group_key,
        CAST(NULL AS nvarchar(50)) AS organisation_code,
        CAST(CASE WHEN l.fact_measure IN ('RAME', 'CAME') THEN 'DEPT AME' ELSE 'DEL ADMIN' END AS varchar(30)) AS control_budget_detail,
        CAST(CASE WHEN l.fact_measure = 'CAME' THEN 'CAPITAL' ELSE 'RESOURCE' END AS varchar(20)) AS economic_budget,
        l.fact_measure AS measure,
        SUM(l.amount_k) AS amount, COUNT(*) AS source_line_count,
        CAST(CASE WHEN l.fact_measure IN ('ADMIN', 'ADMIN_EX_DEPN') THEN 1 ELSE 0 END AS bit) AS is_part_of_other_measure
    FROM pesa_lines AS l
    JOIN pesa_best AS b ON b.year_label = l.year_label AND b.best_seq = l.edition_seq
     AND b.budget_kind = CASE WHEN l.fact_measure IN ('ADMIN', 'ADMIN_EX_DEPN') THEN 'ADMIN' ELSE l.fact_measure END
    JOIN dw.dim_sr_group AS g ON g.sr_group_name = l.target_name
    JOIN dw.dim_plan_source AS ps ON ps.plan_source_code = l.plan_source_code
    WHERE l.line_role <> 'component'
    GROUP BY ps.plan_source_key, l.year_label, g.sr_group_key, l.fact_measure
),
allrows AS (
    SELECT * FROM estimates
    UNION ALL SELECT * FROM pesa
)
INSERT INTO dw.fact_plan
    (plan_fact_key, plan_source_key, financial_year, sr_group_key, organisation_code, control_budget_detail,
     economic_budget, measure, amount, grain_code, source_line_count, is_part_of_other_measure)
SELECT
    ROW_NUMBER() OVER (ORDER BY a.plan_source_key, a.financial_year, a.sr_group_key, a.organisation_code,
                                a.control_budget_detail, a.economic_budget, a.measure),
    a.plan_source_key, a.financial_year, a.sr_group_key, a.organisation_code, a.control_budget_detail,
    a.economic_budget, a.measure, a.amount, a.grain_code, a.source_line_count, a.is_part_of_other_measure
FROM allrows AS a;
GO

-- a key that identifies a row without its surrogate: used by tests and by anything that merges plan rows
CREATE UNIQUE INDEX ux_dw_fact_plan_natural ON dw.fact_plan
    (plan_source_key, financial_year, sr_group_key, organisation_code, control_budget_detail, economic_budget, measure);
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'Spending plans from OSCAR Plans, the Estimates and PESA, at four grains (grain_code). Real published numbers only; the Spending Review group each line belongs to comes from the authored name map. GBP thousands.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'fact_plan';
GO
