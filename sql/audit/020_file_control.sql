-- audit.file_control: one row per in-year data file, the loaded figures next to the expected ones
-- from data/audit/inyear_file_control_totals.csv, with pass / fail / not loaded per measure.
--   raw  : rows and the exact amount sum straight from raw.oscar_inyear
--   stg  : rows and the DECIMAL(19,4) sum from stg.inyear_snapshot (zero-amount rows dropped)
--   twin : the March 2026 ODS is a second copy of the zip's data; it is read, compared, not loaded.

DROP TABLE IF EXISTS audit.file_control;
GO

WITH raw_agg AS (
    SELECT file_id,
           COUNT_BIG(*) AS rows_loaded,
           SUM(CASE WHEN amount_whole = 0 AND amount_frac = 0 THEN 1 ELSE 0 END) AS zero_rows,
           SUM(CASE WHEN NOT (amount_whole = 0 AND amount_frac = 0)
                     AND CAST(amount_whole AS decimal(19,4)) + CAST(amount_frac AS decimal(19,4)) = 0
                    THEN 1 ELSE 0 END) AS rounds_to_zero_rows,
           SUM(amount_whole) AS sum_whole,
           SUM(amount_frac)  AS sum_frac
    FROM raw.oscar_inyear
    GROUP BY file_id
), quarantine_agg AS (
    SELECT file_id, COUNT_BIG(*) AS rows_quarantined
    FROM quarantine.oscar_inyear
    GROUP BY file_id
), stg_agg AS (
    SELECT file_id, COUNT_BIG(*) AS staged_rows, SUM(amount) AS staged_amount_sum
    FROM stg.inyear_snapshot
    GROUP BY file_id
), c AS (
SELECT
    f.file_id,
    f.release,
    f.filename,
    f.container,
    f.primary_for_release,
    f.load_status,
    f.sha256_file AS sha256,
    CAST(CASE WHEN f.sha256_file = f.sha256_manifest AND f.sha256_file = e.sha256 THEN 'pass' ELSE 'fail' END AS varchar(12)) AS sha256_status,
    f.data_rows AS rows_read,
    e.data_rows AS rows_read_expected,
    ISNULL(a.rows_loaded, 0) AS rows_loaded,
    ISNULL(q.rows_quarantined, 0) AS rows_quarantined,
    CAST(CASE WHEN f.data_rows <> e.data_rows THEN 'fail'
              WHEN f.primary_for_release = 'N' THEN 'not loaded'
              WHEN f.data_rows = ISNULL(a.rows_loaded, 0) + ISNULL(q.rows_quarantined, 0) THEN 'pass'
              ELSE 'fail' END AS varchar(12)) AS rows_status,
    ISNULL(a.zero_rows, 0) AS zero_rows,
    ISNULL(a.rounds_to_zero_rows, 0) AS rounds_to_zero_rows,
    e.zero_rows AS zero_rows_expected,
    CAST(CASE WHEN f.primary_for_release = 'N' THEN 'not loaded'
              WHEN ISNULL(a.zero_rows, 0) = e.zero_rows THEN 'pass' ELSE 'fail' END AS varchar(12)) AS zero_rows_status,
    CAST(CASE WHEN a.file_id IS NULL THEN NULL
              ELSE audit.exact_sum_text(a.sum_whole, a.sum_frac) END AS varchar(100)) AS amount_sum_exact,
    e.amount_sum AS amount_sum_expected,
    CAST(CASE WHEN f.primary_for_release = 'N' THEN 'not loaded'
              WHEN audit.exact_sum_text(a.sum_whole, a.sum_frac) = e.amount_sum THEN 'pass' ELSE 'fail' END AS varchar(12)) AS amount_sum_status,
    ISNULL(s.staged_rows, 0) AS staged_rows,
    e.data_rows - e.zero_rows AS staged_rows_expected,
    CAST(CASE WHEN f.primary_for_release = 'N' THEN 'not loaded'
              WHEN ISNULL(s.staged_rows, 0) = e.data_rows - e.zero_rows THEN 'pass' ELSE 'fail' END AS varchar(12)) AS staged_rows_status,
    s.staged_amount_sum,
    CAST(e.amount_sum_rounded_4dp AS decimal(38,4)) AS amount_sum_4dp_expected,
    CAST(CASE WHEN f.primary_for_release = 'N' THEN 'not loaded'
              WHEN s.staged_amount_sum = CAST(e.amount_sum_rounded_4dp AS decimal(38,4)) THEN 'pass' ELSE 'fail' END AS varchar(12)) AS staged_sum_status,
    f.duplicate_of_file_id,
    f.duplicate_identical,
    CAST(CASE WHEN f.primary_for_release = 'Y' THEN 'n/a'
              WHEN f.duplicate_identical = 1 AND f.data_rows = e.data_rows AND ISNULL(a.rows_loaded, 0) = 0 THEN 'pass'
              ELSE 'fail' END AS varchar(12)) AS twin_status
FROM raw.oscar_inyear_file AS f
JOIN raw.oscar_inyear_control_expected AS e ON e.release = f.release AND e.filename = f.filename
LEFT JOIN raw_agg AS a ON a.file_id = f.file_id
LEFT JOIN quarantine_agg AS q ON q.file_id = f.file_id
LEFT JOIN stg_agg AS s ON s.file_id = f.file_id
)
SELECT
    c.*,
    CAST(CASE WHEN 'fail' IN (c.sha256_status, c.rows_status, c.zero_rows_status, c.amount_sum_status,
                              c.staged_rows_status, c.staged_sum_status, c.twin_status)
              THEN 'fail' ELSE 'pass' END AS varchar(12)) AS overall_status
INTO audit.file_control
FROM c;
GO

ALTER TABLE audit.file_control ALTER COLUMN file_id int NOT NULL;
GO
ALTER TABLE audit.file_control ADD CONSTRAINT pk_audit_file_control PRIMARY KEY (file_id);
GO
