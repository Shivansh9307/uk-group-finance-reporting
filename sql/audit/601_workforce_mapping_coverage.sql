-- scope: full
-- audit.workforce_mapping_coverage: per department series and month of the primary files, how many published rows the
-- map placed on an organisation and how many it did not, and the full-time equivalent and paybill that goes with them.
--   rows_*       published rows (non-blank rows of the data sheet), by what the load did with them; rows_empty are the
--                template's spare rows (no name, every value zero or blank) and are not counted in rows_total
--   fte_*        the rows' published payroll full-time equivalent: how many rows have one, and the sum
--   paybill_*    the same for the published payroll paybill, in pounds
--   mapped = placed on a durable organisation (dw.workforce_month); the rest is in quarantine.workforce_row
--   Rows with no value do not count towards the fte and paybill columns (a footnote row has a name and no numbers).

DROP TABLE IF EXISTS audit.workforce_mapping_coverage;
GO

CREATE TABLE audit.workforce_mapping_coverage (
    dept                 varchar(20)    NOT NULL,
    report_month         char(7)        NOT NULL,
    rows_total           int            NOT NULL,   -- organisation rows: every row but the spare template rows
    rows_empty           int            NOT NULL,
    rows_mapped          int            NOT NULL,
    rows_excluded        int            NOT NULL,
    rows_unmapped        int            NOT NULL,   -- no_map_row, no_organisation_name, period_not_file_month
    fte_rows_total       int            NOT NULL,
    fte_rows_mapped      int            NOT NULL,
    fte_total            decimal(38,10) NOT NULL,
    fte_mapped           decimal(38,10) NOT NULL,
    paybill_rows_total   int            NOT NULL,
    paybill_rows_mapped  int            NOT NULL,
    paybill_total        decimal(38,10) NOT NULL,
    paybill_mapped       decimal(38,10) NOT NULL,
    CONSTRAINT pk_audit_workforce_mapping_coverage PRIMARY KEY (dept, report_month)
);
GO

WITH r AS (
    SELECT c.dept, c.report_month, c.status,
           MAX(CASE WHEN v.measure_key = 'payroll_total_fte' THEN v.value END) AS fte,
           MAX(CASE WHEN v.measure_key = 'cost_payroll_paybill_gbp' THEN v.value END) AS paybill
    FROM stg.workforce_row_class AS c
    LEFT JOIN raw.workforce_value AS v ON v.file_id = c.file_id AND v.source_row = c.source_row
                                      AND v.measure_key IN ('payroll_total_fte', 'cost_payroll_paybill_gbp')
    GROUP BY c.file_id, c.source_row, c.dept, c.report_month, c.status
)
INSERT INTO audit.workforce_mapping_coverage
SELECT dept, report_month,
       SUM(CASE WHEN status <> 'empty_row' THEN 1 ELSE 0 END),
       SUM(CASE WHEN status = 'empty_row' THEN 1 ELSE 0 END),
       SUM(CASE WHEN status = 'mapped' THEN 1 ELSE 0 END),
       SUM(CASE WHEN status = 'excluded' THEN 1 ELSE 0 END),
       SUM(CASE WHEN status NOT IN ('mapped', 'excluded', 'empty_row') THEN 1 ELSE 0 END),
       SUM(CASE WHEN fte IS NOT NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN fte IS NOT NULL AND status = 'mapped' THEN 1 ELSE 0 END),
       COALESCE(SUM(fte), 0),
       COALESCE(SUM(CASE WHEN status = 'mapped' THEN fte END), 0),
       SUM(CASE WHEN paybill IS NOT NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN paybill IS NOT NULL AND status = 'mapped' THEN 1 ELSE 0 END),
       COALESCE(SUM(paybill), 0),
       COALESCE(SUM(CASE WHEN status = 'mapped' THEN paybill END), 0)
FROM r
GROUP BY dept, report_month;
GO
