-- scope: full
-- audit.workforce_row_arithmetic: the published rows whose own total is not the sum of their own components, so that a
-- reader of dw.workforce_month can see where a source cell is wrong. Nothing is corrected: the published total is what
-- the fact holds, and the finding is listed here.
--   payroll_fte, payroll_headcount   the row's payroll total against the sum of its six grade columns; flagged when they
--                                    differ by more than 1 person
--   payroll_paybill_gbp              the row's total paybill against salary + allowances + non-consolidated payments +
--                                    overtime + employer pension + employer national insurance; flagged when they differ
--                                    by more than 1,000 pounds
--   Only primary files, and only rows with a published total above zero and at least one component.
-- sql/tests/618 pins how many findings there are for each check.

DROP TABLE IF EXISTS audit.workforce_row_arithmetic;
GO

CREATE TABLE audit.workforce_row_arithmetic (
    dept               varchar(20)    NOT NULL,
    report_month       char(7)        NOT NULL,
    filename           nvarchar(260)  NOT NULL,
    source_row         int            NOT NULL,
    organisation_name  nvarchar(400)  NOT NULL,
    check_key          varchar(30)    NOT NULL,
    published_total    decimal(38,10) NOT NULL,
    sum_of_components  decimal(38,10) NOT NULL,
    difference         decimal(38,10) NOT NULL,
    CONSTRAINT pk_audit_workforce_row_arithmetic PRIMARY KEY (dept, report_month, filename, source_row, check_key)
);
GO

WITH r AS (
    SELECT v.file_id, v.source_row,
           MAX(CASE WHEN v.measure_key = 'payroll_total_fte' THEN v.value END) AS tot_fte,
           SUM(CASE WHEN v.measure_key IN ('payroll_ao_aa_fte', 'payroll_eo_fte', 'payroll_seo_heo_fte', 'payroll_grade_6_7_fte',
                                           'payroll_scs_fte', 'payroll_other_fte') THEN v.value END) AS parts_fte,
           MAX(CASE WHEN v.measure_key = 'payroll_total_hc' THEN v.value END) AS tot_hc,
           SUM(CASE WHEN v.measure_key IN ('payroll_ao_aa_hc', 'payroll_eo_hc', 'payroll_seo_heo_hc', 'payroll_grade_6_7_hc',
                                           'payroll_scs_hc', 'payroll_other_hc') THEN v.value END) AS parts_hc,
           MAX(CASE WHEN v.measure_key = 'cost_payroll_paybill_gbp' THEN v.value END) AS tot_pay,
           SUM(CASE WHEN v.measure_key IN ('cost_salary_gbp', 'cost_allowances_gbp', 'cost_non_consolidated_gbp',
                                           'cost_overtime_gbp', 'cost_employer_pension_gbp', 'cost_employer_ni_gbp') THEN v.value END) AS parts_pay
    FROM raw.workforce_value AS v
    JOIN raw.workforce_file AS f ON f.file_id = v.file_id AND f.is_primary = 1
    GROUP BY v.file_id, v.source_row
),
x AS (
    SELECT file_id, source_row, 'payroll_fte' AS check_key, tot_fte AS tot, parts_fte AS parts, 1 AS tol FROM r
    UNION ALL SELECT file_id, source_row, 'payroll_headcount', tot_hc, parts_hc, 1 FROM r
    UNION ALL SELECT file_id, source_row, 'payroll_paybill_gbp', tot_pay, parts_pay, 1000 FROM r
)
INSERT INTO audit.workforce_row_arithmetic
SELECT f.dept, f.report_month, f.filename, x.source_row, w.organisation_name, x.check_key, x.tot, x.parts, x.tot - x.parts
FROM x
JOIN raw.workforce_file AS f ON f.file_id = x.file_id
JOIN raw.workforce_row AS w ON w.file_id = x.file_id AND w.source_row = x.source_row
WHERE x.tot > 0 AND x.parts IS NOT NULL AND ABS(x.tot - x.parts) > x.tol;
GO
