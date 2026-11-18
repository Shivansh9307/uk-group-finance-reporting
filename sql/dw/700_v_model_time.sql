-- The model's view layer, part 1: the time dimensions and the scenario. Every view is a plain select of the
-- columns the semantic model needs, under stable snake_case names; the model renames them to business names.
-- No business rule lives here. The model reads views, never tables, so a change to a warehouse table
-- is one change to a view and not an edit of the model's partitions.
--   dw.v_model_fiscal_year    one row per financial year of dw.dim_period (the join target of the plan, which
--                             is published by year)
--   dw.v_model_fiscal_period  dw.dim_period
--   dw.v_model_release        dw.dim_release
--   dw.v_model_scenario       dw.dim_scenario

DROP VIEW IF EXISTS dw.v_model_fiscal_year;
GO
CREATE VIEW dw.v_model_fiscal_year
AS
SELECT financial_year, fiscal_year_start
FROM dw.dim_period
GROUP BY financial_year, fiscal_year_start
UNION
SELECT DISTINCT p.financial_year, CAST(LEFT(p.financial_year, 4) AS smallint)
FROM dw.fact_plan AS p
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_period AS d WHERE d.financial_year = p.financial_year);
GO

DROP VIEW IF EXISTS dw.v_model_fiscal_period;
GO
CREATE VIEW dw.v_model_fiscal_period
AS
SELECT period_key, financial_year, period, period_label, month_name, month_start_date, fiscal_quarter,
       is_period0
FROM dw.dim_period;
GO

DROP VIEW IF EXISTS dw.v_model_release;
GO
CREATE VIEW dw.v_model_release
AS
SELECT release_key, label, display_label, release_seq, financial_year, first_published, highest_period,
       release_in_year, version_label, is_latest_release, is_year_end_release
FROM dw.dim_release;
GO

DROP VIEW IF EXISTS dw.v_model_scenario;
GO
CREATE VIEW dw.v_model_scenario
AS
SELECT scenario_key, scenario_name, sort_order, is_derived, description
FROM dw.dim_scenario;
GO
