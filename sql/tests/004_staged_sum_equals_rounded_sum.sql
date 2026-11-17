-- test: the staged DECIMAL(19,4) sum equals amount_sum_rounded_4dp for every release
-- Rounding each amount to four places moves a file total by up to GBP 5.44k, so the staged table is
-- compared with the rounded control total, not the exact one.

SELECT f.release, f.filename, CAST(e.amount_sum_rounded_4dp AS decimal(38,4)) AS expected_rounded_sum,
       s.staged_sum
FROM raw.oscar_inyear_file AS f
JOIN raw.oscar_inyear_control_expected AS e ON e.release = f.release AND e.filename = f.filename
LEFT JOIN (
    SELECT release, SUM(amount) AS staged_sum FROM stg.inyear_snapshot GROUP BY release
) AS s ON s.release = f.release
WHERE f.primary_for_release = 'Y'
  AND (s.release IS NULL OR s.staged_sum <> CAST(e.amount_sum_rounded_4dp AS decimal(38,4)));
