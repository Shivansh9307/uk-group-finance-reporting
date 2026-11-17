-- audit.plan_sheet_control: the control on every plan table that was loaded.
--   For each table section and year, the published total row is compared with the sum of the lines above it.
--   The total row is read from the workbook like any other cell and is not summed by the loader, so
--   this checks the load against the sheet's own arithmetic.
--   - lines: the 'line' rows above the first total row of the section, except lines that the authored name
--     map marks as 'component' (already inside another line, e.g. 'Reserve excluding retained Budget
--     Exchanges' inside 'Reserves'). Lines below the first total row belong to a later total.
--   - tolerance: the published figures are rounded, so each line can be out by half a unit of the last
--     published digit; tolerance = (lines + 1) x 0.5 x 10^-d with d the most decimal places of any figure in
--     that section and year, at most 9 (0 for the PESA tables in pound millions, 3 or 6 for the Estimates in
--     pound billions; the SR25 workbook is unrounded, so its limit is 9).
--   - status: pass | fail | no total (the total is blank for that year).
--   Sections that have lines but no total row, and sections without lines, are not listed.
--   Only the nominal department-group tables are in stg (see stg/520), so the Total Managed Expenditure tables,
--   the real-terms tables and the national-accounts tables are outside this control.
-- Amounts here are in the unit the sheet publishes (pound billions or pound millions), not in GBP thousands.

DROP TABLE IF EXISTS audit.plan_sheet_control;
GO

CREATE TABLE audit.plan_sheet_control (
    family           varchar(20)    NOT NULL,   -- estimates | pesa
    edition          varchar(30)    NOT NULL,
    sheet            nvarchar(100)  NOT NULL,
    section          nvarchar(400)  NOT NULL,
    year_label       varchar(7)     NOT NULL,
    status_label     varchar(20)    NOT NULL,   -- plans | outturn as labelled in the sheet
    measure          varchar(40)    NOT NULL,
    unit             nvarchar(100)  NOT NULL,
    total_label      nvarchar(400)  NOT NULL,
    line_count       int            NOT NULL,
    lines_sum        decimal(38,18) NOT NULL,
    published_total  decimal(38,18) NULL,
    difference       decimal(38,18) NULL,       -- published total minus the sum of lines
    tolerance        decimal(38,18) NOT NULL,
    status           varchar(10)    NOT NULL,   -- pass | fail | no total
    CONSTRAINT pk_audit_plan_sheet_control PRIMARY KEY (family, edition, sheet, section, year_label)
);
GO

WITH s AS (
    SELECT 'estimates' AS family, l.file_id, l.edition, l.sheet, l.section, l.year_label, l.status_label, l.measure,
           l.unit, l.source_row, l.row_kind, l.row_label_clean, l.value_published, l.line_role, r.value_text
    FROM stg.plan_estimates_line AS l
    JOIN raw.plan_estimates AS r
      ON r.file_id = l.file_id AND r.sheet = l.sheet AND r.source_row = l.source_row AND r.year_label = l.year_label
    UNION ALL
    SELECT 'pesa', l.file_id, l.edition, l.sheet, l.section, l.year_label, l.status_label, l.measure,
           l.unit, l.source_row, l.row_kind, l.row_label_clean, l.value_published, l.line_role, r.value_text
    FROM stg.plan_pesa_line AS l
    JOIN raw.plan_pesa AS r
      ON r.file_id = l.file_id AND r.sheet = l.sheet AND r.source_row = l.source_row AND r.year_label = l.year_label
),
first_total AS (
    SELECT file_id, sheet, section, year_label, MIN(source_row) AS total_row
    FROM s WHERE row_kind = 'total'
    GROUP BY file_id, sheet, section, year_label
),
agg AS (
    SELECT t.file_id, t.sheet, t.section, t.year_label, t.total_row,
           COUNT(CASE WHEN l.row_kind = 'line' AND (l.line_role IS NULL OR l.line_role <> 'component') THEN 1 END) AS line_count,
           COALESCE(SUM(CASE WHEN l.row_kind = 'line' AND (l.line_role IS NULL OR l.line_role <> 'component')
                             THEN l.value_published END), 0) AS lines_sum,
           -- at most 9 places: the SR25 workbook carries unrounded 15-digit figures, whose sums differ by about 1e-13
           LEAST(9, MAX(CASE WHEN l.value_text LIKE '%.%' THEN LEN(l.value_text) - CHARINDEX('.', l.value_text) ELSE 0 END)) AS decimals
    FROM first_total AS t
    JOIN s AS l
      ON l.file_id = t.file_id AND l.sheet = t.sheet AND l.section = t.section AND l.year_label = t.year_label
     AND l.source_row <= t.total_row
    GROUP BY t.file_id, t.sheet, t.section, t.year_label, t.total_row
)
INSERT INTO audit.plan_sheet_control
    (family, edition, sheet, section, year_label, status_label, measure, unit, total_label, line_count, lines_sum,
     published_total, difference, tolerance, status)
SELECT
    tt.family, tt.edition, tt.sheet, tt.section, tt.year_label, tt.status_label, tt.measure, tt.unit,
    tt.row_label_clean, a.line_count, a.lines_sum, tt.value_published,
    tt.value_published - a.lines_sum,
    CAST((a.line_count + 1) * 0.5 / POWER(CAST(10 AS decimal(38,18)), a.decimals) AS decimal(38,18)),
    CASE WHEN tt.value_published IS NULL THEN 'no total'
         WHEN ABS(tt.value_published - a.lines_sum) <= (a.line_count + 1) * 0.5 / POWER(CAST(10 AS decimal(38,18)), a.decimals) THEN 'pass'
         ELSE 'fail' END
FROM agg AS a
JOIN s AS tt
  ON tt.file_id = a.file_id AND tt.sheet = a.sheet AND tt.section = a.section AND tt.year_label = a.year_label
 AND tt.source_row = a.total_row AND tt.row_kind = 'total'
WHERE a.line_count > 0;
GO
