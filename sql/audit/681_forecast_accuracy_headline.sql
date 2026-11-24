-- scope: full
-- audit.forecast_accuracy_headline: the headline accuracy of the three forecasts for each financial year, from
-- dw.forecast_accuracy, pooled over the returns R1 to R11 (the points at which both my methods exist and at least one month
-- is left to forecast) and over every department group x budget measure (RDEL, CDEL, AME) of the year.
--   method          department (the department's own forecast in return n), run_rate, seasonal (dw.forecast_own)
--   version         'all returns' or 'excluding flagged returns' (department groups in dw.forecast_return_quality removed
--                   from the same return)
--   cells           (department group, budget measure, return) cells compared
--   scope_cells, scope_value  the cells (and the sum of |full-year outturn|, GBP thousands) of every department group x budget
--                   measure x return R1 to R11 of the year in this version: the cells a method could cover
--   value           the sum of |full-year outturn| of the cells the method covers; coverage_cells = cells / scope_cells and
--                   coverage_value = value / scope_value. The seasonal method exists only where its guard holds (sql/dw/660),
--                   so its coverage is below 1 and the cells it leaves out are visible here, not hidden; the WAPE of every
--                   method is on the cells it covers, and dept_* is the department on the same cells
--   wape            full-year WAPE: sum of |full-year forecast - full-year outturn| / sum of |full-year outturn|
--   bias            signed: sum of (full-year forecast - full-year outturn) / sum of |full-year outturn|; positive = over-forecast
--   fm_wape, fm_bias  the same two on the forecast months only (months n + 1 to 12, month by month)
--   dept_wape, dept_bias, dept_fm_wape, dept_fm_bias  the department's own forecast on exactly the same cells, so that a
--                   method is always compared with the department on the cells where it exists
-- WAPE is a ratio of sums, never an average of line percentages.

DROP TABLE IF EXISTS audit.forecast_accuracy_headline;
GO

CREATE TABLE audit.forecast_accuracy_headline (
    financial_year  varchar(7)     NOT NULL,
    method          varchar(10)    NOT NULL,
    version         varchar(30)    NOT NULL,
    cells           int            NOT NULL,
    scope_cells     int            NOT NULL,
    value           decimal(19,4)  NOT NULL,
    scope_value     decimal(19,4)  NOT NULL,
    coverage_cells  decimal(19,10) NOT NULL,
    coverage_value  decimal(19,10) NULL,
    wape            decimal(19,10) NULL,
    bias            decimal(19,10) NULL,
    fm_wape         decimal(19,10) NULL,
    fm_bias         decimal(19,10) NULL,
    dept_wape       decimal(19,10) NULL,
    dept_bias       decimal(19,10) NULL,
    dept_fm_wape    decimal(19,10) NULL,
    dept_fm_bias    decimal(19,10) NULL,
    CONSTRAINT pk_audit_forecast_accuracy_headline PRIMARY KEY (financial_year, method, version)
);
GO

WITH versions AS (
    SELECT v.version, v.flagged_ok FROM (VALUES ('all returns', 1), ('excluding flagged returns', 0)) AS v (version, flagged_ok)
),
base AS (
    SELECT a.financial_year, a.method, a.is_flagged_return,
           a.full_year_error, a.full_year_abs_error, a.full_year_abs_outturn, a.fm_error, a.fm_abs_error, a.fm_abs_outturn,
           d.full_year_error AS d_full_year_error, d.full_year_abs_error AS d_full_year_abs_error,
           d.full_year_abs_outturn AS d_full_year_abs_outturn, d.fm_error AS d_fm_error, d.fm_abs_error AS d_fm_abs_error,
           d.fm_abs_outturn AS d_fm_abs_outturn
    FROM dw.forecast_accuracy AS a
    JOIN dw.forecast_accuracy AS d
      ON d.financial_year = a.financial_year AND d.return_no = a.return_no AND d.department_group_code = a.department_group_code
     AND d.budget_measure = a.budget_measure AND d.method = 'department'
    WHERE a.return_no BETWEEN 1 AND 11
)
INSERT INTO audit.forecast_accuracy_headline
    (financial_year, method, version, cells, scope_cells, value, scope_value, coverage_cells, coverage_value,
     wape, bias, fm_wape, fm_bias, dept_wape, dept_bias, dept_fm_wape, dept_fm_bias)
SELECT b.financial_year, b.method, v.version, COUNT(*), sc.scope_cells, SUM(b.full_year_abs_outturn), sc.scope_value,
       CAST(COUNT(*) AS decimal(19, 10)) / sc.scope_cells,
       CASE WHEN sc.scope_value <> 0 THEN CAST(SUM(b.full_year_abs_outturn) AS decimal(30, 10)) / sc.scope_value END,
       CASE WHEN SUM(b.full_year_abs_outturn) <> 0 THEN CAST(SUM(b.full_year_abs_error) AS decimal(30, 10)) / SUM(b.full_year_abs_outturn) END,
       CASE WHEN SUM(b.full_year_abs_outturn) <> 0 THEN CAST(SUM(b.full_year_error) AS decimal(30, 10)) / SUM(b.full_year_abs_outturn) END,
       CASE WHEN SUM(b.fm_abs_outturn) <> 0 THEN CAST(SUM(b.fm_abs_error) AS decimal(30, 10)) / SUM(b.fm_abs_outturn) END,
       CASE WHEN SUM(b.fm_abs_outturn) <> 0 THEN CAST(SUM(b.fm_error) AS decimal(30, 10)) / SUM(b.fm_abs_outturn) END,
       CASE WHEN SUM(b.d_full_year_abs_outturn) <> 0 THEN CAST(SUM(b.d_full_year_abs_error) AS decimal(30, 10)) / SUM(b.d_full_year_abs_outturn) END,
       CASE WHEN SUM(b.d_full_year_abs_outturn) <> 0 THEN CAST(SUM(b.d_full_year_error) AS decimal(30, 10)) / SUM(b.d_full_year_abs_outturn) END,
       CASE WHEN SUM(b.d_fm_abs_outturn) <> 0 THEN CAST(SUM(b.d_fm_abs_error) AS decimal(30, 10)) / SUM(b.d_fm_abs_outturn) END,
       CASE WHEN SUM(b.d_fm_abs_outturn) <> 0 THEN CAST(SUM(b.d_fm_error) AS decimal(30, 10)) / SUM(b.d_fm_abs_outturn) END
FROM base AS b
CROSS JOIN versions AS v
JOIN (SELECT a.financial_year, vv.version, COUNT(*) AS scope_cells, SUM(a.full_year_abs_outturn) AS scope_value
      FROM dw.forecast_accuracy AS a CROSS JOIN versions AS vv
      WHERE a.method = 'department' AND a.return_no BETWEEN 1 AND 11 AND (vv.flagged_ok = 1 OR a.is_flagged_return = 0)
      GROUP BY a.financial_year, vv.version) AS sc ON sc.financial_year = b.financial_year AND sc.version = v.version
WHERE v.flagged_ok = 1 OR b.is_flagged_return = 0
GROUP BY b.financial_year, b.method, v.version, sc.scope_cells, sc.scope_value;
GO
