-- Independent of the model: the control of the load (audit.file_control, one primary file per release). The as-at figure
-- the model computes from the deltas must equal the total the file reports, so the expected as-at is that total and the
-- expected difference is 0.
SELECT release, CAST(rows_read AS bigint) AS rows_read, rows_loaded, rows_quarantined,
       amount_sum_exact AS file_sum_exact,
       CAST(amount_sum_4dp_expected AS decimal(38, 4)) AS file_total,
       CAST(amount_sum_4dp_expected AS decimal(38, 4)) AS as_at,
       CAST(0 AS decimal(38, 4)) AS difference
FROM audit.file_control
WHERE primary_for_release = 'Y'
ORDER BY release;
