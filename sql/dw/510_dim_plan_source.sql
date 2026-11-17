-- dw.dim_plan_source: one row per plan source and edition that was loaded.
--   OSCAR Plans (annual extracts, November 2022), each Estimates workbook (Main, out-of-turn Supplementary,
--   Supplementary) per plan year, each PESA edition and the Spending Review 2025 DEL tables.
-- The descriptive columns (grain, plan basis, block grant adjustment rule, resource basis) are authored
-- (authored/plan_source.csv, typed in stg.plan_source) with their evidence; the file name, hash, publication date and the number of
-- rows each edition contributes to dw.fact_plan come from the load. is_final_plan_for_year marks the
-- Estimates workbook that fact_plan uses for each plan year. A PESA edition is used for the plan years in
-- which it is the latest edition that still calls the year 'plans' (see dw/520_fact_plan.sql).
-- The key follows the order of authored/plan_source.csv, so a source keeps its key in both build scopes.
-- In a committed-scope build the OSCAR extracts are not read, so that row is absent and so is its rows in fact_plan.
-- fact_plan_rows is set in dw/520_fact_plan.sql once the fact exists.

DROP TABLE IF EXISTS dw.dim_plan_source;
GO

CREATE TABLE dw.dim_plan_source (
    plan_source_key       int            NOT NULL CONSTRAINT pk_dw_dim_plan_source PRIMARY KEY,
    plan_source_code      varchar(40)    NOT NULL,
    family                varchar(20)    NOT NULL,   -- oscar_extract | estimates | pesa | sr25
    edition               varchar(30)    NOT NULL,
    edition_label         nvarchar(200)  NOT NULL,
    plan_year             varchar(7)     NULL,       -- the one plan year of an Estimates workbook, NULL otherwise
    first_published       date           NULL,
    file_count            int            NOT NULL,   -- files read for this edition (five for the OSCAR extracts)
    filename              nvarchar(260)  NOT NULL,   -- the file, or the first of several
    sha256                char(64)       NULL,       -- of the file; NULL when there are several
    grain_description     nvarchar(400)  NOT NULL,
    plan_basis            nvarchar(200)  NOT NULL,
    includes_block_grant_adjustment varchar(30) NOT NULL,
    scotland_bga_flag     varchar(30)    NOT NULL,   -- net_of_bga | gross_of_bga | same_as_oscar_outturn | not_applicable
    scotland_bga_rule     nvarchar(1000) NOT NULL,
    resource_basis        varchar(20)    NOT NULL,   -- as_titled | ex_depreciation
    resource_basis_evidence nvarchar(1000) NOT NULL,
    is_final_plan_for_year bit           NOT NULL,   -- Estimates: the workbook fact_plan uses for plan_year
    fact_plan_rows        int            NOT NULL,   -- set by dw/520_fact_plan.sql
    CONSTRAINT uq_dw_dim_plan_source_code UNIQUE (plan_source_code)
);
GO

WITH a AS (
    SELECT s.*,
           ROW_NUMBER() OVER (ORDER BY CASE s.family WHEN 'oscar_extract' THEN 1 WHEN 'estimates' THEN 2 WHEN 'pesa' THEN 3 ELSE 4 END,
                                       s.edition_seq) AS rn
    FROM stg.plan_source AS s
)
INSERT INTO dw.dim_plan_source
    (plan_source_key, plan_source_code, family, edition, edition_label, plan_year, first_published, file_count, filename, sha256,
     grain_description, plan_basis, includes_block_grant_adjustment, scotland_bga_flag, scotland_bga_rule,
     resource_basis, resource_basis_evidence, is_final_plan_for_year, fact_plan_rows)
SELECT
    a.rn,
    a.plan_source_code, a.family, a.edition, a.edition_label,
    CASE WHEN a.family = 'estimates' THEN LEFT(a.edition, 7) END,
    TRY_CAST(LEFT(f.first_published, 10) AS date),
    f.file_count, f.filename, CASE WHEN f.file_count = 1 THEN f.sha256_file END,
    a.grain_description, a.plan_basis, a.includes_block_grant_adjustment, a.scotland_bga_flag, a.scotland_bga_rule,
    a.resource_basis, a.resource_basis_evidence,
    CAST(CASE WHEN a.family = 'estimates' AND EXISTS (
                   SELECT 1 FROM stg.plan_estimates_line AS l
                   WHERE l.plan_source_code = a.plan_source_code AND l.is_final_plan = 1) THEN 1 ELSE 0 END AS bit),
    0
FROM a
JOIN (
    SELECT family, edition, COUNT(*) AS file_count, MIN(filename) AS filename, MIN(sha256_file) AS sha256_file,
           MIN(first_published) AS first_published
    FROM raw.plan_source_file
    GROUP BY family, edition
) AS f
  ON f.edition = a.edition
 AND f.family = CASE a.family WHEN 'sr25' THEN 'pesa' ELSE a.family END;
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'One row per plan source and edition: OSCAR Plans, each Estimates workbook, each PESA edition, SR25. Descriptive columns are authored (authored/plan_source.csv).',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'dim_plan_source';
GO
