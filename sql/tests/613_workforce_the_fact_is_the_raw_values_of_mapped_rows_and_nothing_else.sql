-- test: for the headline measures, the fact's total of cells that use the file's own total equals, within the 4-decimal rounding, the sum of the raw values of the mapped rows behind those cells (so the authored map moves values between organisations and adds none)
-- marker: localdata
-- requires: dw.workforce_month, stg.workforce_row_class, raw.workforce_value
WITH raw_side AS (
    SELECT w.measure_key, SUM(v.value) AS raw_sum, COUNT(*) AS cells
    FROM stg.workforce_row_class AS c
    JOIN raw.workforce_value AS v ON v.file_id = c.file_id AND v.source_row = c.source_row
    JOIN (VALUES ('payroll_total_fte', 'payroll_fte'), ('payroll_total_hc', 'payroll_headcount'),
                 ('cost_payroll_paybill_gbp', 'payroll_paybill_gbp')) AS k (raw_key, measure_key) ON k.raw_key = v.measure_key
    JOIN dw.workforce_month AS w
      ON w.durable_key = c.durable_key AND w.month_start = c.period_start AND w.measure_key = k.measure_key
    WHERE c.status = 'mapped' AND w.source_priority = 1
    GROUP BY w.measure_key
),
fact_side AS (
    SELECT measure_key, SUM(value) AS fact_sum, SUM(source_rows) AS cells
    FROM dw.workforce_month
    WHERE measure_key IN ('payroll_fte', 'payroll_headcount', 'payroll_paybill_gbp') AND source_priority = 1
    GROUP BY measure_key
)
SELECT r.measure_key, r.raw_sum, f.fact_sum, f.fact_sum - r.raw_sum AS difference, r.cells AS raw_cells, f.cells AS fact_cells
FROM raw_side AS r LEFT JOIN fact_side AS f ON f.measure_key = r.measure_key
WHERE f.fact_sum IS NULL OR ABS(f.fact_sum - r.raw_sum) > 0.00005 * r.cells OR f.cells <> r.cells;
