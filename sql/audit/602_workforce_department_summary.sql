-- scope: full
-- audit.workforce_department_summary: one row per department series (a gov.uk collection, or a run of them under
-- successive names): the months it has files for, how many files and in which formats and templates, the months missing
-- between its first and last month, the largest difference between the loaded and the independently recomputed headline
-- totals, and how much of what it published the authored map placed on an organisation.
--   months_loaded   months with a primary file that was read
--   months_missing  calendar months between first_month and last_month with no file read (gaps in publication, and the
--                   files in raw.workforce_file with load_status skipped)
--   fte_diff_max, paybill_diff_max   largest absolute difference over the department's files, payroll full-time
--                   equivalent and payroll paybill, loaded minus recomputed; 0 means exact
--   coverage_*      share of rows, of payroll full-time equivalent and of payroll paybill that are on an organisation
--                   (the rest is in quarantine.workforce_row)
-- Months are those the series publishes from April 2018 (the first month that overlaps the OSCAR releases).

DROP TABLE IF EXISTS audit.workforce_department_summary;
GO

CREATE TABLE audit.workforce_department_summary (
    dept              varchar(20)    NOT NULL CONSTRAINT pk_audit_workforce_department_summary PRIMARY KEY,
    first_month       char(7)        NOT NULL,
    last_month        char(7)        NOT NULL,
    months_loaded     int            NOT NULL,
    months_missing    int            NOT NULL,
    files             int            NOT NULL,
    files_skipped     int            NOT NULL,
    formats           varchar(40)    NOT NULL,
    templates         varchar(60)    NOT NULL,
    fte_diff_max      decimal(38,10) NOT NULL,
    paybill_diff_max  decimal(38,10) NOT NULL,
    rows_total        int            NOT NULL,   -- organisation rows (the template's spare rows are not counted)
    rows_mapped       int            NOT NULL,
    coverage_rows     decimal(9,4)   NULL,
    coverage_fte      decimal(9,4)   NULL,
    coverage_paybill  decimal(9,4)   NULL
);
GO

WITH f AS (
    SELECT dept, MIN(report_month) AS first_month, MAX(report_month) AS last_month,
           COUNT(DISTINCT CASE WHEN is_primary = 1 THEN report_month END) AS months_loaded,
           COUNT(*) AS files, SUM(CASE WHEN load_status = 'skipped' THEN 1 ELSE 0 END) AS files_skipped
    FROM raw.workforce_file GROUP BY dept
),
fmt AS (
    SELECT DISTINCT dept, format FROM raw.workforce_file WHERE load_status = 'loaded'
),
tpl AS (
    SELECT DISTINCT dept, template FROM raw.workforce_file WHERE load_status = 'loaded'
),
ctl AS (
    SELECT dept,
           MAX(CASE WHEN measure_key IN ('payroll_total_fte', 'payroll_total_hc') THEN ABS(difference_sum) END) AS fte_diff,
           MAX(CASE WHEN measure_key = 'cost_payroll_paybill_gbp' THEN ABS(difference_sum) END) AS paybill_diff
    FROM audit.workforce_file_control_totals GROUP BY dept
),
cov AS (
    SELECT dept, SUM(rows_total) AS rows_total, SUM(rows_mapped) AS rows_mapped,
           SUM(fte_total) AS fte_total, SUM(fte_mapped) AS fte_mapped,
           SUM(paybill_total) AS paybill_total, SUM(paybill_mapped) AS paybill_mapped
    FROM audit.workforce_mapping_coverage GROUP BY dept
)
INSERT INTO audit.workforce_department_summary
SELECT f.dept, f.first_month, f.last_month, f.months_loaded,
       DATEDIFF(month, CAST(f.first_month + '-01' AS date), CAST(f.last_month + '-01' AS date)) + 1 - f.months_loaded,
       f.files, f.files_skipped,
       (SELECT STRING_AGG(x.format, '+') WITHIN GROUP (ORDER BY x.format) FROM fmt AS x WHERE x.dept = f.dept),
       (SELECT STRING_AGG(x.template, '+') WITHIN GROUP (ORDER BY x.template) FROM tpl AS x WHERE x.dept = f.dept),
       COALESCE(c.fte_diff, 0), COALESCE(c.paybill_diff, 0),
       COALESCE(v.rows_total, 0), COALESCE(v.rows_mapped, 0),
       CAST(100.0 * COALESCE(v.rows_mapped, 0) / NULLIF(v.rows_total, 0) AS decimal(9, 4)),
       CAST(100.0 * COALESCE(v.fte_mapped, 0) / NULLIF(v.fte_total, 0) AS decimal(9, 4)),
       CAST(100.0 * COALESCE(v.paybill_mapped, 0) / NULLIF(v.paybill_total, 0) AS decimal(9, 4))
FROM f
LEFT JOIN ctl AS c ON c.dept = f.dept
LEFT JOIN cov AS v ON v.dept = f.dept;
GO
