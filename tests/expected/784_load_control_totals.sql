-- requires: audit.bud_file_control
-- Independent of the model: the two control tables the view unions, grouped. Web quarantines are empty (test 705).
SELECT source_family, COUNT(*) AS files, CAST(SUM(rows_read) AS bigint) AS rows_read, CAST(SUM(rows_loaded) AS bigint) AS rows_loaded,
       CAST(SUM(rows_quarantined) AS bigint) AS rows_quarantined, CAST(0 AS bigint) AS web_rows_quarantined
FROM (
    SELECT 'In-year release' AS source_family, rows_read, rows_loaded, rows_quarantined FROM audit.file_control WHERE primary_for_release = 'Y'
    UNION ALL
    SELECT 'Annual restated file', rows_read, rows_loaded, rows_quarantined FROM audit.bud_file_control
) AS x
GROUP BY source_family
ORDER BY source_family;
