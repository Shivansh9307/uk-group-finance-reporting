-- scope: full
-- dw.outturn_plan_basis_annual: annual outturn on the plan's exact basis, by Spending Review group, from the
-- annual restated outturn (BUD) workbooks.
--   Grain: vintage x financial year x Spending Review group x measure.
--   Measures:
--     RDEL           control budget DEL, economic budget RESOURCE (depreciation and other ringfenced items in)
--     RDEL_EX_DEPN   basis_rdel_excl_depreciation = 1: DEL, RESOURCE and ECONOMIC_RINGFENCE_CODE <> 'RINGFENCED',
--                    the basis the Estimates and the Spending Review use
--     CDEL           control budget DEL, economic budget CAPITAL
--   The group is the BUD's own Spending Review group of the organisation (stg.bud_sr_group_by_organisation), not
--   the bridge of the in-year outturn, so that the comparison reproduces the published groups. Its code is matched
--   to dw.dim_sr_group; a group the current list does not have (Foreign and Commonwealth Office, Exiting the
--   European Union, the 'n/a' of the central exchequer lines) goes where authored/plan_name_map.csv puts that
--   name (family oscar_extract). A group that matches neither stops the build.
--   is_latest_vintage              the newest annual release loaded
--   is_latest_vintage_for_year     the newest vintage that holds the financial year
-- Real outturn, regrouped. Measures overlap (RDEL_EX_DEPN is part of RDEL); never add them.

DROP TABLE IF EXISTS dw.outturn_plan_basis_annual;
GO

CREATE TABLE dw.outturn_plan_basis_annual (
    vintage                     varchar(7)     NOT NULL,
    financial_year              varchar(7)     NOT NULL,
    sr_group_key                int            NOT NULL,
    measure                     varchar(40)    NOT NULL,
    amount                      decimal(19,4)  NOT NULL,
    source_rows                 int            NOT NULL,
    is_latest_vintage           bit            NOT NULL,
    is_latest_vintage_for_year  bit            NOT NULL,
    CONSTRAINT pk_dw_outturn_plan_basis_annual PRIMARY KEY (vintage, financial_year, sr_group_key, measure)
);
GO

DECLARE @unmatched nvarchar(1000) = (
    SELECT STRING_AGG(x.label, '; ') WITHIN GROUP (ORDER BY x.label)
    FROM (SELECT DISTINCT b.sr_group_code + ' ' + b.sr_group_name AS label
          FROM stg.bud_sr_group_by_organisation AS b
          WHERE NOT EXISTS (SELECT 1 FROM dw.dim_sr_group AS g WHERE g.sr_group_code = b.sr_group_code)
            AND NOT EXISTS (SELECT 1 FROM stg.plan_name_map AS m
                            JOIN dw.dim_sr_group AS g ON g.sr_group_name = m.target_name
                            WHERE m.name_family = 'oscar_extract' AND m.plan_name = b.sr_group_name)) AS x);
IF @unmatched IS NOT NULL
BEGIN
    DECLARE @msg nvarchar(1100) = N'a BUD Spending Review group has no member in dw.dim_sr_group: ' + @unmatched;
    THROW 50575, @msg, 1;
END
GO

WITH grp AS (
    SELECT b.vintage, b.financial_year, b.organisation_code,
           COALESCE(gc.sr_group_key, gn.sr_group_key) AS sr_group_key
    FROM stg.bud_sr_group_by_organisation AS b
    LEFT JOIN dw.dim_sr_group AS gc ON gc.sr_group_code = b.sr_group_code
    LEFT JOIN stg.plan_name_map AS m ON m.name_family = 'oscar_extract' AND m.plan_name = b.sr_group_name AND gc.sr_group_key IS NULL
    LEFT JOIN dw.dim_sr_group AS gn ON gn.sr_group_name = m.target_name
), lines AS (
    SELECT f.vintage, f.financial_year, g.sr_group_key, ms.measure, f.amount, f.source_rows, CAST(f.is_latest_vintage AS int) AS is_latest
    FROM dw.fact_outturn_annual AS f
    JOIN grp AS g ON g.vintage = f.vintage AND g.financial_year = f.financial_year AND g.organisation_code = f.organisation_code
    CROSS APPLY (VALUES
        ('RDEL',         CASE WHEN f.control_budget_code = 'DEL' AND f.economic_budget_code = 'RESOURCE' THEN 1 ELSE 0 END),
        ('RDEL_EX_DEPN', CAST(f.basis_rdel_excl_depreciation AS int)),
        ('CDEL',         CASE WHEN f.control_budget_code = 'DEL' AND f.economic_budget_code = 'CAPITAL' THEN 1 ELSE 0 END)
    ) AS ms (measure, selected)
    WHERE ms.selected = 1
), agg AS (
    SELECT vintage, financial_year, sr_group_key, measure, SUM(amount) AS amount, SUM(CAST(source_rows AS bigint)) AS source_rows,
           MAX(is_latest) AS is_latest
    FROM lines
    GROUP BY vintage, financial_year, sr_group_key, measure
)
INSERT INTO dw.outturn_plan_basis_annual
    (vintage, financial_year, sr_group_key, measure, amount, source_rows, is_latest_vintage, is_latest_vintage_for_year)
SELECT a.vintage, a.financial_year, a.sr_group_key, a.measure, CAST(a.amount AS decimal(19, 4)), CAST(a.source_rows AS int),
       CAST(a.is_latest AS bit),
       CAST(CASE WHEN a.vintage = MAX(a.vintage) OVER (PARTITION BY a.financial_year) THEN 1 ELSE 0 END AS bit)
FROM agg AS a;
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'Annual restated outturn (BUD) on the plan''s exact basis (RDEL, RDEL excluding depreciation by the ringfence column, CDEL) by the BUD''s own Spending Review group, for every vintage. Real outturn, regrouped. Measures overlap; never add them.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'outturn_plan_basis_annual';
GO
