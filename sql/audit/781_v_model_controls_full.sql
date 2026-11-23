-- scope: full
-- The model's view layer, part 9: the data controls that need the files that are not in git (the annual restated
-- files and the Public Spending Statistics database), so they exist only after a full build.
--   dw.v_model_annual_control  audit.bud_vs_inyear_del: the in-year outturn of a year against the restated annual
--                              file, by vintage and level. Only DEL at total level is graded.
--   dw.v_model_pss_control     audit.pss_vs_outturn: the Public Spending Statistics database against OSCAR outturn,
--                              by year, Spending Review group and measure.
--   dw.v_model_load_control    the rows read, loaded and quarantined of every in-year file and every annual file.
-- Columns are copied from the audit tables; no amount is recalculated.

DROP VIEW IF EXISTS dw.v_model_annual_control;
GO
CREATE VIEW dw.v_model_annual_control
AS
SELECT financial_year, vintage, level, inyear_release, inyear_amount, bud_amount, gap, gap_share_of_bud, tolerance_share,
       status, is_latest_vintage_for_year, basis_note
FROM audit.bud_vs_inyear_del;
GO

DROP VIEW IF EXISTS dw.v_model_pss_control;
GO
CREATE VIEW dw.v_model_pss_control
AS
SELECT comparison, financial_year, source_release, level, sr_group_name, measure, pss_amount, oscar_amount, gap,
       gap_share_of_oscar, tolerance_share, status, basis_note
FROM audit.pss_vs_outturn;
GO

DROP VIEW IF EXISTS dw.v_model_load_control;
GO
CREATE VIEW dw.v_model_load_control
AS
SELECT CAST('In-year release' AS varchar(20)) AS source_family, release AS source_period, filename,
       rows_read, rows_loaded, rows_quarantined, overall_status
FROM audit.file_control
WHERE primary_for_release = 'Y'
UNION ALL
SELECT 'Annual restated file', vintage + ' ' + financial_year, filename, rows_read, rows_loaded, rows_quarantined, overall_status
FROM audit.bud_file_control;
GO
