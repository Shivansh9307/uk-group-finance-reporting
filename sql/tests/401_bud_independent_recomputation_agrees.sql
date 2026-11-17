-- test: the loaded BUD data agrees with the independent recomputation (data/audit/bud_independent_control.csv)
-- marker: localdata
-- requires: raw.oscar_bud, raw.oscar_bud_file, raw.oscar_bud_independent_expected
SELECT i.vintage, i.filename, a.n AS rows_loaded, i.data_rows AS rows_independent,
       a.sum_all AS sum_loaded, i.amount_sum_all_rows AS sum_independent,
       a.sum_excl_closed AS sum_excl_closed_loaded, i.amount_sum_excluding_closed AS sum_excl_closed_independent
FROM raw.oscar_bud_independent_expected AS i
LEFT JOIN (
    SELECT f.vintage, f.filename, f.financial_year,
           COUNT_BIG(*) AS n,
           SUM(r.amount) AS sum_all,
           SUM(CASE WHEN r.status_code <> 'Closed' THEN r.amount ELSE 0 END) AS sum_excl_closed,
           SUM(CASE WHEN r.status_code = 'Closed' THEN 1 ELSE 0 END) AS closed_rows
    FROM raw.oscar_bud AS r
    JOIN raw.oscar_bud_file AS f ON f.file_id = r.file_id
    GROUP BY f.vintage, f.filename, f.financial_year
) AS a ON a.vintage = i.vintage AND a.filename = i.filename
WHERE a.n IS NULL
   OR a.n <> i.data_rows
   OR a.financial_year <> i.financial_year
   OR a.sum_all <> i.amount_sum_all_rows
   OR a.sum_excl_closed <> i.amount_sum_excluding_closed
   OR a.closed_rows <> i.closed_rows;
