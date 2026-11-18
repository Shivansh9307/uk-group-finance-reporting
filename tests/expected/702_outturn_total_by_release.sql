-- Independent of the fact and of the model: the total each release file reports, from the committed control
-- totals (amount_sum_rounded_4dp), loaded into audit.file_control. One row per release (the twin file of March 2026
-- is not primary).
SELECT release AS release, CAST(amount_sum_4dp_expected AS decimal(38, 4)) AS as_at_total
FROM audit.file_control
WHERE primary_for_release = 'Y'
ORDER BY release;
