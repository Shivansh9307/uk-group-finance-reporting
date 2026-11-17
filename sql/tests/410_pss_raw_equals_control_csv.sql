-- test: raw.pss rows and amount sums equal data/audit/pss_file_control_totals.csv and the independent recomputation, for every year
-- marker: localdata
-- requires: raw.pss, raw.pss_file, raw.pss_control_expected, raw.pss_independent_expected
SELECT e.financial_year, a.n AS rows_loaded, i.data_rows AS rows_independent,
       a.s AS sum_loaded, e.amount_total AS sum_expected, i.amount_sum AS sum_independent
FROM raw.pss_control_expected AS e
LEFT JOIN raw.pss_independent_expected AS i ON i.filename = e.filename AND i.financial_year = e.financial_year
LEFT JOIN (
    SELECT f.filename, p.[year] AS financial_year, COUNT_BIG(*) AS n, SUM(p.amount) AS s
    FROM raw.pss AS p
    JOIN raw.pss_file AS f ON f.file_id = p.file_id
    GROUP BY f.filename, p.[year]
) AS a ON a.filename = e.filename AND a.financial_year = e.financial_year
WHERE a.n IS NULL OR i.data_rows IS NULL
   OR a.n <> i.data_rows
   OR a.s <> e.amount_total
   OR a.s <> i.amount_sum
UNION ALL
SELECT N'total rows <> the control total_rows', CAST(t.n AS bigint), e.total_rows, NULL, NULL, NULL
FROM (SELECT COUNT_BIG(*) AS n FROM raw.pss) AS t
CROSS JOIN (SELECT MAX(total_rows) AS total_rows FROM raw.pss_control_expected) AS e
WHERE t.n <> e.total_rows
UNION ALL
SELECT N'years <> 5', COUNT(*), NULL, NULL, NULL, NULL
FROM raw.pss_control_expected HAVING COUNT(*) <> 5
UNION ALL
SELECT N'database file not loaded or Chapter 1 tables not recorded as skipped', COUNT(*), NULL, NULL, NULL, NULL
FROM raw.pss_file
WHERE NOT ((file_kind = 'database' AND load_status = 'loaded' AND sha256_file = sha256_manifest)
        OR (file_kind = 'tables' AND load_status = 'skipped' AND skip_reason <> N'' AND data_rows = 0))
HAVING COUNT(*) > 0;
