-- scope: full
-- audit.tac_file_control_totals: one row per data workbook and worksheet of `All data`, the loaded figures next to
-- the independent ones from data/audit/tac_independent_control.csv (`ukfr control tac`: python-calamine, no code
-- shared with the reader).
--   rows_expected / value_sum_expected   the independent recomputation, every worksheet
--   rows_read                            what the reader counted (raw.tac_worksheet)
--   rows_loaded, rows_rejected           raw.tac_value and quarantine.tac_value, the three statements only
--   value_sum_raw, difference            exact sum of the loaded values and its difference from the expected sum
--   value_sum_stg, rounded_sum_raw       DECIMAL(19,4) sum in stg.tac_value against the per-row rounding of raw
--   rows_unmapped, rows_fact, value_sum_fact   the step into dw.tac_fact: loaded = fact + unmapped, and the sum
--                                        of stg = fact + unmapped
-- A worksheet of notes is counted and not loaded (loaded = 0): its rows are checked, its sums are in the
-- expected column only. status is pass when every comparison that applies is exact.

DROP TABLE IF EXISTS audit.tac_file_control_totals;
GO

WITH raw_agg AS (
    SELECT file_id, worksheet_name, COUNT_BIG(*) AS rows_loaded, SUM(value) AS value_sum_raw,
           SUM(CAST(value AS decimal(19,4))) AS rounded_sum_raw
    FROM raw.tac_value GROUP BY file_id, worksheet_name
), rejected AS (
    SELECT file_id, JSON_VALUE(row_json, '$.worksheet_name') AS worksheet_name, COUNT_BIG(*) AS rows_rejected
    FROM quarantine.tac_value GROUP BY file_id, JSON_VALUE(row_json, '$.worksheet_name')
), stg_agg AS (
    SELECT file_id, worksheet_name, COUNT_BIG(*) AS rows_stg, SUM(value) AS value_sum_stg
    FROM stg.tac_value GROUP BY file_id, worksheet_name
), fact_agg AS (
    SELECT f.file_id, v.worksheet_name, COUNT_BIG(*) AS rows_fact, SUM(f.value) AS value_sum_fact
    FROM dw.tac_fact AS f
    JOIN stg.tac_value AS v ON v.file_id = f.file_id AND v.source_row = f.source_row
    GROUP BY f.file_id, v.worksheet_name
), unmapped_agg AS (
    SELECT u.file_id, v.worksheet_name, COUNT_BIG(*) AS rows_unmapped, SUM(u.value) AS value_sum_unmapped
    FROM quarantine.tac_unmapped_row AS u
    JOIN stg.tac_value AS v ON v.file_id = u.file_id AND v.source_row = u.source_row
    GROUP BY u.file_id, v.worksheet_name
), c AS (
    SELECT COALESCE(f.release, e.release) AS release,
           COALESCE(f.filename, e.filename) AS filename,
           f.provider_type,
           COALESCE(w.worksheet_name, e.worksheet_name) AS worksheet_name,
           ISNULL(w.loaded, 0) AS loaded,
           e.data_rows AS rows_expected,
           w.data_rows AS rows_read,
           ISNULL(a.rows_loaded, 0) AS rows_loaded,
           ISNULL(q.rows_rejected, 0) AS rows_rejected,
           e.value_sum AS value_sum_expected,
           a.value_sum_raw,
           a.value_sum_raw - e.value_sum AS difference,
           s.value_sum_stg,
           a.rounded_sum_raw,
           s.value_sum_stg - a.rounded_sum_raw AS difference_stg,
           ISNULL(u.rows_unmapped, 0) AS rows_unmapped,
           ISNULL(g.rows_fact, 0) AS rows_fact,
           g.value_sum_fact,
           s.value_sum_stg - ISNULL(g.value_sum_fact, 0) - ISNULL(u.value_sum_unmapped, 0) AS difference_fact
    FROM raw.tac_worksheet AS w
    JOIN raw.tac_file AS f ON f.file_id = w.file_id
    FULL OUTER JOIN raw.tac_independent_expected AS e ON e.filename = f.filename AND e.worksheet_name = w.worksheet_name
    LEFT JOIN raw_agg AS a ON a.file_id = w.file_id AND a.worksheet_name = w.worksheet_name
    LEFT JOIN rejected AS q ON q.file_id = w.file_id AND q.worksheet_name = w.worksheet_name
    LEFT JOIN stg_agg AS s ON s.file_id = w.file_id AND s.worksheet_name = w.worksheet_name
    LEFT JOIN fact_agg AS g ON g.file_id = w.file_id AND g.worksheet_name = w.worksheet_name
    LEFT JOIN unmapped_agg AS u ON u.file_id = w.file_id AND u.worksheet_name = w.worksheet_name
)
SELECT c.*,
       CAST(CASE WHEN c.rows_expected IS NULL OR c.rows_read IS NULL OR c.rows_expected <> c.rows_read THEN 'fail'
                 WHEN c.loaded = 0 THEN 'pass'
                 WHEN c.rows_read <> c.rows_loaded + c.rows_rejected THEN 'fail'
                 WHEN c.difference <> 0 OR c.difference_stg <> 0 OR c.difference_fact <> 0 THEN 'fail'
                 WHEN c.rows_loaded <> c.rows_fact + c.rows_unmapped THEN 'fail'
                 ELSE 'pass' END AS varchar(10)) AS status
INTO audit.tac_file_control_totals
FROM c;
GO

ALTER TABLE audit.tac_file_control_totals ALTER COLUMN release varchar(7) NOT NULL;
GO
ALTER TABLE audit.tac_file_control_totals ALTER COLUMN filename nvarchar(260) NOT NULL;
GO
ALTER TABLE audit.tac_file_control_totals ALTER COLUMN worksheet_name nvarchar(60) NOT NULL;
GO
ALTER TABLE audit.tac_file_control_totals ADD CONSTRAINT pk_audit_tac_file_control_totals
    PRIMARY KEY (release, filename, worksheet_name);
GO
