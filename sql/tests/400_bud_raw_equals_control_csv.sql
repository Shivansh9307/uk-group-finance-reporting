-- test: raw.oscar_bud rows and exact sums equal data/audit/bud_file_control_totals.csv for each of the 15 workbooks
-- marker: localdata
-- requires: raw.oscar_bud, raw.oscar_bud_file, raw.oscar_bud_control_expected
SELECT e.vintage, e.filename, CAST(a.n AS bigint) AS rows_loaded, e.data_rows AS rows_expected,
       a.sum_all AS sum_loaded, e.amount_sum_all_rows AS sum_expected
FROM raw.oscar_bud_control_expected AS e
LEFT JOIN (
    SELECT f.vintage, f.filename,
           COUNT_BIG(*) AS n,
           SUM(r.amount) AS sum_all,
           SUM(CASE WHEN r.status_code <> 'Closed' THEN r.amount ELSE 0 END) AS sum_excl_closed,
           SUM(CASE WHEN r.status_code = 'Closed' THEN 1 ELSE 0 END) AS closed_rows,
           SUM(CASE WHEN r.status_code = 'Closed' THEN r.amount ELSE 0 END) AS sum_closed,
           SUM(CASE WHEN r.status_code <> 'Closed' AND r.control_budget_l1_long_name = 'DEL' THEN r.amount ELSE 0 END) AS sum_del,
           SUM(CASE WHEN r.status_code <> 'Closed' AND r.control_budget_l1_long_name = 'AME' THEN r.amount ELSE 0 END) AS sum_ame,
           SUM(CASE WHEN r.status_code <> 'Closed' AND r.control_budget_l1_long_name = 'NON-BUDGET' THEN r.amount ELSE 0 END) AS sum_nb
    FROM raw.oscar_bud AS r
    JOIN raw.oscar_bud_file AS f ON f.file_id = r.file_id
    GROUP BY f.vintage, f.filename
) AS a ON a.vintage = e.vintage AND a.filename = e.filename
WHERE a.n IS NULL
   OR a.n <> e.data_rows
   OR a.sum_all <> e.amount_sum_all_rows
   OR a.sum_excl_closed <> e.amount_sum_excluding_closed
   OR a.closed_rows <> e.closed_rows
   OR a.sum_closed <> e.amount_closed
   OR a.sum_del <> e.amount_del OR a.sum_ame <> e.amount_ame OR a.sum_nb <> e.amount_non_budget
UNION ALL
SELECT N'expected file count', N'<>15', (SELECT COUNT(*) FROM raw.oscar_bud_control_expected), 15, NULL, NULL
WHERE (SELECT COUNT(*) FROM raw.oscar_bud_control_expected) <> 15
UNION ALL
SELECT f.vintage, f.filename, NULL, NULL, NULL, NULL
FROM raw.oscar_bud_file AS f
WHERE f.file_kind = 'data'
  AND NOT EXISTS (SELECT 1 FROM raw.oscar_bud_control_expected AS e WHERE e.vintage = f.vintage AND e.filename = f.filename);
