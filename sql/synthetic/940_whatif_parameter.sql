-- phase: pre
-- synthetic.whatif_parameter: the settings of a what-if on the allocation page. SYNTHETIC: each row is a scenario I invented, so
-- that a reader can see what a pay award and a headcount change would do to the allocated amounts and to the paybill. It holds
-- percentages, not amounts, and nothing real is built from it: the what-if measures read it and no real fact, view of a fact or
-- real measure does (sql/tests/940 and pipeline/tests/test_register.py).
--   pay_award_pct         the pay award in per cent. The base setting takes the ONS CPI annual rate (series D7G7) for the calendar year
--                         2025, 3.4 per cent, from the file the repository already holds (data/raw/ons_cpi, manifest source ons_cpi);
--                         the other settings move it by a round invented number of points
--   headcount_change_pct  the change in headcount in per cent; no ONS series in the repository gives it, so every value is invented
--   pay_award_basis, headcount_basis   say where each percentage comes from: 'ONS D7G7 annual rate, 2025' or 'invented'
--   data_class            always 'synthetic'
-- The table is created here (not by the loader) so that the types and checks are in the schema; the loader only empties it and
-- writes the file's rows. A change to the shape needs `ukfr build --recreate`.

IF OBJECT_ID(N'synthetic.whatif_parameter') IS NULL
BEGIN
    CREATE TABLE synthetic.whatif_parameter (
        _load_order           int            NOT NULL CONSTRAINT pk_synthetic_whatif_parameter PRIMARY KEY,
        setting_key           int            NOT NULL,
        setting_name          nvarchar(60)   NOT NULL,
        pay_award_pct         decimal(9,4)   NOT NULL,
        headcount_change_pct  decimal(9,4)   NOT NULL,
        pay_award_basis       nvarchar(60)   NOT NULL,
        headcount_basis       nvarchar(60)   NOT NULL,
        is_default            bit            NOT NULL,
        data_class            varchar(20)    NOT NULL,
        note                  nvarchar(1000) NOT NULL,
        CONSTRAINT ck_synthetic_whatif_parameter_class CHECK (data_class = 'synthetic'),
        CONSTRAINT uq_synthetic_whatif_parameter_key UNIQUE (setting_key),
        CONSTRAINT uq_synthetic_whatif_parameter_name UNIQUE (setting_name),
        CONSTRAINT ck_synthetic_whatif_parameter_range CHECK (pay_award_pct BETWEEN -20 AND 50 AND headcount_change_pct BETWEEN -50 AND 50)
    );
END
GO

IF EXISTS (SELECT 1 FROM sys.extended_properties
           WHERE class = 1 AND major_id = OBJECT_ID(N'synthetic.whatif_parameter') AND minor_id = 0 AND name = N'MS_Description')
    EXEC sys.sp_dropextendedproperty @name = N'MS_Description',
        @level0type = N'SCHEMA', @level0name = N'synthetic', @level1type = N'TABLE', @level1name = N'whatif_parameter';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'SYNTHETIC data, loaded from synthetic/whatif_parameter.csv: invented what-if settings (a pay award and a headcount change, in per cent) for the allocation page. The base pay award is the ONS CPI annual rate for 2025; every other value is invented. It holds percentages and no amount, and is never part of a real total.',
    @level0type = N'SCHEMA', @level0name = N'synthetic', @level1type = N'TABLE', @level1name = N'whatif_parameter';
GO
