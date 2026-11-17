-- dw.dim_scenario: the five scenarios the model compares. Static rows. Only Outturn is loaded by the
-- in-year fact (dw.fact_outturn); the others are filled by later tables, and the description says which of
-- them are derived rather than read from a source file.
--   is_derived   1 = computed in the warehouse from other scenarios or from a method, not published

DROP TABLE IF EXISTS dw.dim_scenario;
GO

CREATE TABLE dw.dim_scenario (
    scenario_key   int           NOT NULL CONSTRAINT pk_dw_dim_scenario PRIMARY KEY,
    scenario_name  nvarchar(50)  NOT NULL,
    sort_order     int           NOT NULL,
    is_derived     bit           NOT NULL,
    description    nvarchar(500) NOT NULL,
    CONSTRAINT uq_dw_dim_scenario_name UNIQUE (scenario_name)
);
GO

INSERT INTO dw.dim_scenario (scenario_key, scenario_name, sort_order, is_derived, description)
VALUES
 (1, N'Outturn', 1, 0, N'What departments reported as spent, month by month, in each OSCAR in-year release. Published, not derived.'),
 (2, N'Plan', 2, 0, N'The annual budget: OSCAR Plans and the Estimates, as published. Not derived. Held for the year, not by month.'),
 (3, N'Plan (phased)', 3, 1, N'The annual plan spread across months by a stated phasing rule. Derived: the monthly values are not published.'),
 (4, N'Departments'' forecast', 4, 0, N'The monthly forecast each department sent to HM Treasury (Main Forecast Outturn returns), as published. Not derived.'),
 (5, N'Own forecast', 5, 1, N'A forecast I build in the warehouse from outturn and plans. Derived: it is not a published number and never mixes into the other scenarios.');
GO
