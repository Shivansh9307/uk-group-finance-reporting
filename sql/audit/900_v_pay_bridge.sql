-- scope: full
-- The pay bridge: the views that split the change in paybill, month against the same month a year earlier, into
-- volume, rate and organisation mix, and the views the semantic model reads.
-- DERIVED from real data (dw.workforce_month); nothing authored or synthetic is added. The files sit in the audit layer
-- because the rule that drops a published row whose total is not its components reads audit.workforce_row_arithmetic.
--
--   dw.v_pay_cell          one row per durable organisation and month with a published payroll full-time equivalent or
--                          paybill: the two values, the department of the current structure the body sat in that month,
--                          and a status. A cell is 'valid' unless one of these holds (first match decides):
--                            fte_blank_or_zero      no full-time equivalent, or zero
--                            paybill_blank_or_zero  no paybill, or zero or negative (the average cost needs a paybill)
--                            row_arithmetic         a published row behind the cell is listed in
--                                                   audit.workforce_row_arithmetic for its full-time equivalent or paybill
--   dw.v_pay_bridge_row    one row per department, organisation and month (the month is the later of the two compared),
--                          with bridge_class continuing | entry | exit | not_bridged
--   dw.v_model_pay_bridge, dw.v_model_pay_organisation, dw.v_model_pay_coverage    plain selects for the model
--
-- The department is the department of the current structure that the organisation version in force in the month answers
-- to (dw.department_reported_number): the version with the latest start on or before the month, or the first version when
-- the month is before every start. A body that moved department between the two months is an exit from the first and an
-- entry to the second.
--
-- Classes (a month m is compared with m minus 12 months):
--   continuing  valid in both months and in the same department: the bridge splits the change into volume and rate
--   entry       valid in m and not in m minus 12 (no cell, or a body that was in another department then)
--   exit        valid in m minus 12 and not in m (no cell, or a body in another department now)
--   not_bridged left out, with a reason: comparison_cell_excluded (the cell of the other month exists and is not valid)
--               or department_not_comparable (the department has no valid cell in one of the two months, so an entry or
--               exit would only mean that the data is missing)
-- volume_org = (fte_cur - fte_prior) x average cost of the prior month; rate_org = pay_cur - pay_prior - volume_org, which
-- is fte_cur x (average cost now - average cost then) with the rounding of volume_org kept out of the sum. A department
-- level volume and mix are computed over the rows of a selection by the measures and by audit.pay_bridge_tie.

DROP VIEW IF EXISTS dw.v_model_pay_bridge;
GO
DROP VIEW IF EXISTS dw.v_model_pay_organisation;
GO
DROP VIEW IF EXISTS dw.v_model_pay_coverage;
GO
DROP VIEW IF EXISTS dw.v_pay_bridge_row;
GO
DROP VIEW IF EXISTS dw.v_pay_cell;
GO

CREATE VIEW dw.v_pay_cell
AS
WITH c AS (
    SELECT w.durable_key, w.month_start, w.report_month,
           MAX(CASE WHEN w.measure_key = 'payroll_fte' THEN w.value END) AS fte,
           MAX(CASE WHEN w.measure_key = 'payroll_paybill_gbp' THEN w.value END) AS paybill
    FROM dw.workforce_month AS w
    WHERE w.measure_key IN ('payroll_fte', 'payroll_paybill_gbp')
    GROUP BY w.durable_key, w.month_start, w.report_month
),
flagged AS (
    SELECT DISTINCT k.durable_key, k.period_start AS month_start
    FROM audit.workforce_row_arithmetic AS a
    JOIN raw.workforce_file AS f ON f.dept = a.dept AND f.report_month = a.report_month AND f.filename = a.filename
    JOIN stg.workforce_row_class AS k ON k.file_id = f.file_id AND k.source_row = a.source_row AND k.status = 'mapped'
    WHERE a.check_key IN ('payroll_fte', 'payroll_paybill_gbp')
)
SELECT c.durable_key, c.month_start, c.report_month,
       CAST((CASE WHEN MONTH(c.month_start) >= 4 THEN YEAR(c.month_start) ELSE YEAR(c.month_start) - 1 END) * 100
            + ((MONTH(c.month_start) + 8) % 12) + 1 AS int) AS period_key,
       r.current_department_key AS department_key,
       c.fte, c.paybill,
       CAST(CASE WHEN c.fte IS NULL OR c.fte <= 0 THEN 'fte_blank_or_zero'
                 WHEN c.paybill IS NULL OR c.paybill <= 0 THEN 'paybill_blank_or_zero'
                 WHEN f.durable_key IS NOT NULL THEN 'row_arithmetic'
                 ELSE 'valid' END AS varchar(24)) AS cell_status
FROM c
CROSS APPLY (
    SELECT TOP (1) d.department_number
    FROM dw.dim_organisation AS o
    JOIN dw.dim_department AS d ON d.department_key = o.department_key
    WHERE o.durable_key = c.durable_key
    ORDER BY CASE WHEN o.valid_from_release <= c.report_month THEN 0 ELSE 1 END,
             CASE WHEN o.valid_from_release <= c.report_month THEN -o.version_no ELSE o.version_no END
) AS v
JOIN dw.department_reported_number AS r ON r.reported_department_number = v.department_number
LEFT JOIN flagged AS f ON f.durable_key = c.durable_key AND f.month_start = c.month_start;
GO

CREATE VIEW dw.v_pay_bridge_row
AS
WITH p AS (
    SELECT COALESCE(cur.durable_key, pr.durable_key) AS durable_key,
           COALESCE(cur.month_start, DATEADD(YEAR, 1, pr.month_start)) AS month_cur,
           cur.department_key AS cur_dept, cur.fte AS cur_fte, cur.paybill AS cur_pay, cur.cell_status AS cur_status,
           pr.department_key AS pr_dept, pr.fte AS pr_fte, pr.paybill AS pr_pay, pr.cell_status AS pr_status
    FROM dw.v_pay_cell AS cur
    FULL JOIN dw.v_pay_cell AS pr
           ON pr.durable_key = cur.durable_key AND pr.month_start = DATEADD(YEAR, -1, cur.month_start)
),
a AS (   -- the row of the department the body sits in this month
    SELECT durable_key, month_cur, cur_dept AS department_key,
           CASE WHEN pr_status = 'valid' AND pr_dept = cur_dept THEN 'continuing'
                WHEN pr_status IS NULL OR pr_status = 'valid' THEN 'entry'
                ELSE 'not_bridged' END AS cls,
           CAST(CASE WHEN pr_status IS NOT NULL AND pr_status <> 'valid' THEN 'comparison_cell_excluded' END AS varchar(30)) AS reason,
           cur_fte AS fte_cur, cur_pay AS pay_cur,
           CASE WHEN pr_status = 'valid' AND pr_dept = cur_dept THEN pr_fte END AS fte_prior,
           CASE WHEN pr_status = 'valid' AND pr_dept = cur_dept THEN pr_pay END AS pay_prior
    FROM p
    WHERE cur_status = 'valid'
),
b AS (   -- the row of the department the body sat in a year ago, when it is not the same row as above
    SELECT durable_key, month_cur, pr_dept AS department_key,
           CASE WHEN cur_status IS NULL OR cur_status = 'valid' THEN 'exit' ELSE 'not_bridged' END AS cls,
           CAST(CASE WHEN cur_status IS NOT NULL AND cur_status <> 'valid' THEN 'comparison_cell_excluded' END AS varchar(30)) AS reason,
           CAST(NULL AS decimal(19, 4)) AS fte_cur, CAST(NULL AS decimal(19, 4)) AS pay_cur,
           pr_fte AS fte_prior, pr_pay AS pay_prior
    FROM p
    WHERE pr_status = 'valid' AND (cur_status IS NULL OR cur_status <> 'valid' OR cur_dept <> pr_dept)
),
u AS (
    SELECT * FROM a UNION ALL SELECT * FROM b
),
vd AS (
    SELECT DISTINCT department_key, month_start FROM dw.v_pay_cell WHERE cell_status = 'valid'
),
x AS (
    SELECT u.durable_key, u.month_cur, u.department_key,
           CASE WHEN u.cls <> 'not_bridged' AND (c1.department_key IS NULL OR c2.department_key IS NULL)
                THEN 'not_bridged' ELSE u.cls END AS cls,
           CAST(CASE WHEN u.cls <> 'not_bridged' AND (c1.department_key IS NULL OR c2.department_key IS NULL)
                     THEN 'department_not_comparable' ELSE u.reason END AS varchar(30)) AS reason,
           u.fte_cur, u.pay_cur, u.fte_prior, u.pay_prior
    FROM u
    LEFT JOIN vd AS c1 ON c1.department_key = u.department_key AND c1.month_start = u.month_cur
    LEFT JOIN vd AS c2 ON c2.department_key = u.department_key AND c2.month_start = DATEADD(YEAR, -1, u.month_cur)
)
SELECT x.department_key, x.durable_key, x.month_cur AS month_start,
       CAST((CASE WHEN MONTH(x.month_cur) >= 4 THEN YEAR(x.month_cur) ELSE YEAR(x.month_cur) - 1 END) * 100
            + ((MONTH(x.month_cur) + 8) % 12) + 1 AS int) AS period_key,
       CAST(x.cls AS varchar(12)) AS bridge_class, x.reason AS not_bridged_reason,
       x.fte_cur, x.pay_cur, x.fte_prior, x.pay_prior,
       CAST(CASE WHEN x.cls = 'continuing'
                 THEN CAST(x.fte_cur - x.fte_prior AS decimal(24, 10)) * CAST(x.pay_prior AS decimal(24, 10))
                      / CAST(x.fte_prior AS decimal(24, 10)) END AS decimal(19, 4)) AS volume_org
FROM x;
GO

CREATE VIEW dw.v_model_pay_bridge
AS
SELECT department_key, durable_key, period_key, month_start, bridge_class, not_bridged_reason,
       fte_cur, pay_cur, fte_prior, pay_prior, volume_org,
       CAST(CASE WHEN bridge_class = 'continuing' THEN pay_cur - pay_prior - volume_org END AS decimal(19, 4)) AS rate_org
FROM dw.v_pay_bridge_row;
GO

CREATE VIEW dw.v_model_pay_organisation
AS
SELECT o.durable_key, o.organisation_code, o.organisation_name
FROM dw.dim_organisation AS o
WHERE o.is_latest_version = 1
  AND o.durable_key IN (SELECT DISTINCT durable_key FROM dw.workforce_month);
GO

CREATE VIEW dw.v_model_pay_coverage
AS
SELECT CAST(c.dept AS varchar(20)) AS series_code,
       CAST(CASE c.dept WHEN 'beis' THEN 'BEIS' WHEN 'cma' THEN 'CMA' WHEN 'dbt' THEN 'DBT' WHEN 'dcms' THEN 'DCMS'
                        WHEN 'defra' THEN 'Defra' WHEN 'desnz' THEN 'DESNZ' WHEN 'dfe' THEN 'DfE' WHEN 'dft' THEN 'DfT'
                        WHEN 'dhsc' THEN 'DHSC' WHEN 'dsit' THEN 'DSIT' WHEN 'dwp' THEN 'DWP' WHEN 'fcdo' THEN 'FCDO'
                        WHEN 'fsa' THEN 'FSA' WHEN 'hmlr' THEN 'HM Land Registry (own collection)' WHEN 'hmrc' THEN 'HMRC'
                        WHEN 'hmt' THEN 'HM Treasury' WHEN 'mhclg' THEN 'MHCLG' WHEN 'mod' THEN 'MOD'
                        WHEN 'nca' THEN 'NCA' WHEN 'ukef' THEN 'UK Export Finance' ELSE c.dept END AS nvarchar(60)) AS series,
       c.report_month,
       CAST((CASE WHEN CAST(RIGHT(c.report_month, 2) AS int) >= 4 THEN CAST(LEFT(c.report_month, 4) AS int)
                  ELSE CAST(LEFT(c.report_month, 4) AS int) - 1 END) * 100
            + ((CAST(RIGHT(c.report_month, 2) AS int) + 8) % 12) + 1 AS int) AS period_key,
       c.rows_total, c.rows_mapped,
       CAST(c.fte_total AS decimal(19, 4)) AS fte_total, CAST(c.fte_mapped AS decimal(19, 4)) AS fte_mapped,
       CAST(c.paybill_total AS decimal(19, 4)) AS paybill_total, CAST(c.paybill_mapped AS decimal(19, 4)) AS paybill_mapped
FROM audit.workforce_mapping_coverage AS c;
GO

DROP VIEW IF EXISTS dw.v_model_pay_bridge_step;
GO
CREATE VIEW dw.v_model_pay_bridge_step
AS
SELECT CAST(step_order AS int) AS step_order, CAST(step_name AS nvarchar(40)) AS step_name
FROM (VALUES (1, N'Prior paybill'), (2, N'Volume'), (3, N'Rate'), (4, N'Mix'), (5, N'Entry and exit')) AS s (step_order, step_name);
GO
