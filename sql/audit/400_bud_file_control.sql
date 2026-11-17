-- scope: full
-- audit.bud_file_control: one row per BUD workbook (15), the loaded figures beside two sets of expected ones:
--   expected   data/audit/bud_file_control_totals.csv, written by the profiling reader
--   independent data/audit/bud_independent_control.csv, recomputed with python-calamine directly (no shared code)
-- and the fact table built from the workbook. Every measure is pass or fail.
--   rows         rows read = rows loaded + rows quarantined = expected data_rows
--   sums         exact sum of all rows, of every row except STATUS_CODE = 'Closed', and of the Closed rows
--   closed rows  rows with STATUS_CODE = 'Closed' (every one has an identical twin under another status,
--                see the profiling notes); they are left out of dw.fact_outturn_annual and counted here
--   control budget  DEL, AME and NON-BUDGET sums without the Closed rows
--   fact         dw.fact_outturn_annual sums to the workbook total without the Closed rows

DROP TABLE IF EXISTS audit.bud_file_control;
GO

WITH loaded AS (
    SELECT r.file_id,
           COUNT_BIG(*) AS rows_loaded,
           SUM(r.amount) AS amount_sum_all_rows,
           SUM(CASE WHEN r.status_code = 'Closed' THEN 1 ELSE 0 END) AS closed_rows,
           SUM(CASE WHEN r.status_code = 'Closed' THEN r.amount ELSE 0 END) AS amount_closed,
           SUM(CASE WHEN r.status_code <> 'Closed' THEN r.amount ELSE 0 END) AS amount_sum_excluding_closed,
           SUM(CASE WHEN r.status_code <> 'Closed' AND r.control_budget_l1_long_name = 'DEL' THEN r.amount ELSE 0 END) AS amount_del,
           SUM(CASE WHEN r.status_code <> 'Closed' AND r.control_budget_l1_long_name = 'AME' THEN r.amount ELSE 0 END) AS amount_ame,
           SUM(CASE WHEN r.status_code <> 'Closed' AND r.control_budget_l1_long_name = 'NON-BUDGET' THEN r.amount ELSE 0 END) AS amount_non_budget,
           SUM(CASE WHEN r.status_code <> 'Closed'
                     AND r.control_budget_l1_long_name NOT IN ('DEL', 'AME', 'NON-BUDGET') THEN r.amount ELSE 0 END) AS amount_other_control_budget
    FROM raw.oscar_bud AS r
    GROUP BY r.file_id
), quarantined AS (
    SELECT file_id, COUNT_BIG(*) AS rows_quarantined FROM quarantine.oscar_bud GROUP BY file_id
), fact AS (
    SELECT vintage, financial_year, COUNT_BIG(*) AS fact_rows, SUM(source_rows) AS fact_source_rows, SUM(amount) AS fact_amount_sum
    FROM dw.fact_outturn_annual
    GROUP BY vintage, financial_year
), c AS (
    SELECT
        f.file_id,
        f.vintage,
        f.filename,
        f.financial_year,
        f.sha256_file AS sha256,
        CAST(CASE WHEN f.sha256_file = f.sha256_manifest AND f.sha256_file = e.sha256 AND f.sha256_file = i.sha256
                  THEN 'pass' ELSE 'fail' END AS varchar(12)) AS sha256_status,
        f.data_rows AS rows_read,
        e.data_rows AS rows_read_expected,
        i.data_rows AS rows_read_independent,
        l.rows_loaded,
        ISNULL(q.rows_quarantined, 0) AS rows_quarantined,
        CAST(CASE WHEN f.data_rows = e.data_rows AND f.data_rows = i.data_rows
                   AND f.data_rows = l.rows_loaded + ISNULL(q.rows_quarantined, 0) THEN 'pass' ELSE 'fail' END AS varchar(12)) AS rows_status,
        l.closed_rows,
        e.closed_rows AS closed_rows_expected,
        e.closed_rows_with_identical_twin AS closed_rows_with_twin,
        CAST(CASE WHEN l.closed_rows = e.closed_rows AND l.closed_rows = i.closed_rows
                  THEN 'pass' ELSE 'fail' END AS varchar(12)) AS closed_rows_status,
        l.amount_sum_all_rows,
        e.amount_sum_all_rows AS amount_sum_all_rows_expected,
        i.amount_sum_all_rows AS amount_sum_all_rows_independent,
        CAST(CASE WHEN l.amount_sum_all_rows = e.amount_sum_all_rows AND l.amount_sum_all_rows = i.amount_sum_all_rows
                  THEN 'pass' ELSE 'fail' END AS varchar(12)) AS amount_sum_all_rows_status,
        l.amount_closed,
        e.amount_closed AS amount_closed_expected,
        l.amount_sum_excluding_closed,
        e.amount_sum_excluding_closed AS amount_sum_excluding_closed_expected,
        i.amount_sum_excluding_closed AS amount_sum_excluding_closed_independent,
        CAST(CASE WHEN l.amount_closed = e.amount_closed AND l.amount_closed = i.amount_closed
                   AND l.amount_sum_excluding_closed = e.amount_sum_excluding_closed
                   AND l.amount_sum_excluding_closed = i.amount_sum_excluding_closed
                  THEN 'pass' ELSE 'fail' END AS varchar(12)) AS amount_excluding_closed_status,
        l.amount_del,
        l.amount_ame,
        l.amount_non_budget,
        l.amount_other_control_budget,
        CAST(CASE WHEN l.amount_del = e.amount_del AND l.amount_ame = e.amount_ame
                   AND l.amount_non_budget = e.amount_non_budget
                   AND l.amount_other_control_budget = e.amount_other_control_budget
                  THEN 'pass' ELSE 'fail' END AS varchar(12)) AS control_budget_status,
        ISNULL(x.fact_rows, 0) AS fact_rows,
        ISNULL(x.fact_source_rows, 0) AS fact_source_rows,
        x.fact_amount_sum,
        CAST(CASE WHEN x.fact_amount_sum = e.amount_sum_excluding_closed
                   AND ISNULL(x.fact_source_rows, 0) = l.rows_loaded - l.closed_rows
                  THEN 'pass' ELSE 'fail' END AS varchar(12)) AS fact_status
    FROM raw.oscar_bud_file AS f
    JOIN raw.oscar_bud_control_expected AS e ON e.vintage = f.vintage AND e.filename = f.filename
    JOIN raw.oscar_bud_independent_expected AS i ON i.vintage = f.vintage AND i.filename = f.filename
    JOIN loaded AS l ON l.file_id = f.file_id
    LEFT JOIN quarantined AS q ON q.file_id = f.file_id
    LEFT JOIN fact AS x ON x.vintage = f.vintage AND x.financial_year = f.financial_year
    WHERE f.file_kind = 'data'
)
SELECT
    c.*,
    CAST(CASE WHEN 'fail' IN (c.sha256_status, c.rows_status, c.closed_rows_status, c.amount_sum_all_rows_status,
                              c.amount_excluding_closed_status, c.control_budget_status, c.fact_status)
              THEN 'fail' ELSE 'pass' END AS varchar(12)) AS overall_status
INTO audit.bud_file_control
FROM c;
GO

ALTER TABLE audit.bud_file_control ALTER COLUMN file_id int NOT NULL;
GO
ALTER TABLE audit.bud_file_control ADD CONSTRAINT pk_audit_bud_file_control PRIMARY KEY (file_id);
GO
