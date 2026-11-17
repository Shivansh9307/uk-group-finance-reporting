-- test: the exact raw amount sum equals amount_sum of the control table for all primary files
-- whole + frac is the source amount with no rounding; audit.exact_sum_text renders the sum as plain text.

SELECT f.release, f.filename, e.amount_sum AS expected_exact_sum,
       audit.exact_sum_text(a.sum_whole, a.sum_frac) AS raw_exact_sum
FROM raw.oscar_inyear_file AS f
JOIN raw.oscar_inyear_control_expected AS e ON e.release = f.release AND e.filename = f.filename
LEFT JOIN (
    SELECT file_id, SUM(amount_whole) AS sum_whole, SUM(amount_frac) AS sum_frac
    FROM raw.oscar_inyear
    GROUP BY file_id
) AS a ON a.file_id = f.file_id
WHERE f.primary_for_release = 'Y'
  AND (a.file_id IS NULL OR audit.exact_sum_text(a.sum_whole, a.sum_frac) <> e.amount_sum);
