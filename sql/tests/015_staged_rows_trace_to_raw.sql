-- test: every staged row traces to a raw row, keeps its amount rounded to four places, and was not exactly zero
-- Lineage is (file_id, source_row). Rows whose exact amount is zero must have been dropped.

SELECT s.release, s.file_id, s.source_row, s.amount,
       r.amount_whole, r.amount_frac,
       CASE WHEN r.file_id IS NULL THEN 'no raw row'
            WHEN r.amount_whole = 0 AND r.amount_frac = 0 THEN 'exact zero row was staged'
            ELSE 'amount differs from the raw amount rounded to 4 places' END AS problem
FROM stg.inyear_snapshot AS s
LEFT JOIN raw.oscar_inyear AS r ON r.file_id = s.file_id AND r.source_row = s.source_row
WHERE r.file_id IS NULL
   OR (r.amount_whole = 0 AND r.amount_frac = 0)
   OR s.amount <> CAST(CAST(r.amount_whole AS decimal(19,4)) + CAST(r.amount_frac AS decimal(19,4)) AS decimal(19,4))
   OR s.release <> r.release;
