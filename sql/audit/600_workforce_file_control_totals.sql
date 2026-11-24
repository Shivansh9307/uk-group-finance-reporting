-- scope: full
-- audit.workforce_file_control_totals: for every workforce file and each of its headline columns, the count and exact sum
-- of the numeric cells that the loader holds (raw.workforce_value) against the count and exact sum recomputed from the
-- file by ukfr.controls.workforce_independent (raw.workforce_control_expected), which shares no code with the reader.
--   The headline columns are the file's payroll headcount and full-time equivalent, the grand total full-time
--   equivalent, the contingent-labour full-time equivalent (newer files: the total contingent labour; older files: the
--   non-payroll total, which includes consultants), payroll paybill and the grand total paybill.
--   difference_sum   loaded minus expected, exactly; status pass when it is 0 and the counts agree.
--   A column that the reader keyed as a measure but the control has no row for (or the reverse) is a fail.
-- Every column of every file is compared in sql/tests/600; this table keeps the headline ones as evidence.

DROP TABLE IF EXISTS audit.workforce_file_control_totals;
GO

CREATE TABLE audit.workforce_file_control_totals (
    dept             varchar(20)    NOT NULL,
    report_month     char(7)        NOT NULL,
    filename         nvarchar(260)  NOT NULL,
    is_primary       bit            NOT NULL,
    measure_key      varchar(60)    NOT NULL,
    column_index     int            NOT NULL,
    cells_expected   int            NOT NULL,
    cells_loaded     int            NOT NULL,
    sum_expected     decimal(38,10) NOT NULL,
    sum_loaded       decimal(38,10) NOT NULL,
    difference_sum   decimal(38,10) NOT NULL,
    status           varchar(4)     NOT NULL,
    CONSTRAINT pk_audit_workforce_file_control_totals PRIMARY KEY (dept, report_month, filename, measure_key)
);
GO

WITH headline AS (
    SELECT * FROM (VALUES ('payroll_total_hc'), ('payroll_total_fte'), ('grand_total_fte'), ('np_contingent_total_fte'),
                          ('np_total_fte'), ('cost_payroll_paybill_gbp'), ('cost_grand_total_gbp')) AS h (measure_key)
),
cols AS (
    SELECT DISTINCT v.file_id, v.measure_key, v.column_index
    FROM raw.workforce_value AS v JOIN headline AS h ON h.measure_key = v.measure_key
    UNION
    SELECT DISTINCT q.file_id, q.measure_key, q.column_index
    FROM quarantine.workforce_value AS q JOIN headline AS h ON h.measure_key = q.measure_key
),
got AS (
    SELECT file_id, column_index, COUNT_BIG(*) AS n, SUM(value) AS s
    FROM raw.workforce_value GROUP BY file_id, column_index
)
INSERT INTO audit.workforce_file_control_totals
SELECT f.dept, f.report_month, f.filename, f.is_primary, c.measure_key, c.column_index,
       COALESCE(e.numeric_cells, 0), CAST(COALESCE(g.n, 0) AS int),
       COALESCE(e.value_sum, 0), COALESCE(g.s, 0), COALESCE(g.s, 0) - COALESCE(e.value_sum, 0),
       CASE WHEN e.numeric_cells IS NOT NULL AND e.numeric_cells = COALESCE(g.n, 0)
             AND COALESCE(g.s, 0) = e.value_sum THEN 'pass' ELSE 'fail' END
FROM cols AS c
JOIN raw.workforce_file AS f ON f.file_id = c.file_id
LEFT JOIN raw.workforce_control_expected AS e
       ON e.dept = f.dept AND e.report_month = f.report_month AND e.filename = f.filename AND e.column_index = c.column_index
LEFT JOIN got AS g ON g.file_id = c.file_id AND g.column_index = c.column_index;
GO
