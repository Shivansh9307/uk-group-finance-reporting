-- The model's view layer, part 8: the data controls, available at every build scope.
--   dw.v_model_file_control   audit.file_control, one row per release (the primary file of the release), with the
--                             release key the model relates it to. Real: the row counts of the load and the file's
--                             own total. Amounts are never recalculated here: the exact sum is kept as the text the
--                             control produced, the four-decimal total as DECIMAL(19,4).
--   dw.v_model_plan_coverage  dw.plan_coverage with the plan source's name: what the plan fact holds by plan
--                             source, financial year, measure and grain. A count and a total, no new number.
-- The two views are audit and control tables, not fact tables: nothing reads them into an outturn or plan total.

DROP VIEW IF EXISTS dw.v_model_file_control;
GO
CREATE VIEW dw.v_model_file_control
AS
SELECT r.release_key, f.filename, f.rows_read, f.rows_loaded, f.rows_quarantined, f.amount_sum_exact,
       CAST(f.amount_sum_4dp_expected AS decimal(19, 4)) AS file_total_4dp, f.overall_status
FROM audit.file_control AS f
JOIN dw.dim_release AS r ON r.label = f.release
WHERE f.primary_for_release = 'Y';
GO

DROP VIEW IF EXISTS dw.v_model_plan_coverage;
GO
CREATE VIEW dw.v_model_plan_coverage
AS
SELECT s.plan_source_code, s.edition_label AS plan_source, c.financial_year, c.measure, c.grain_code, c.row_count,
       c.source_line_count, c.amount_total
FROM dw.plan_coverage AS c
JOIN dw.dim_plan_source AS s ON s.plan_source_key = c.plan_source_key;
GO
