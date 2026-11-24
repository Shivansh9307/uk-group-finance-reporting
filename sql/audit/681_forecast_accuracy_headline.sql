-- scope: full
-- audit.forecast_accuracy_headline: the headline accuracy of the three forecasts for each financial year, from
-- dw.forecast_accuracy, pooled over the returns R1 to R11 (the points at which both my methods exist and at least one month
-- is left to forecast) and over every department group x budget measure (RDEL, CDEL, AME) of the year.
--   method          department (the department's own forecast in return n), run_rate, seasonal (dw.forecast_own)
--   version         'all returns' or 'excluding flagged returns' (department groups in dw.forecast_return_quality removed
--                   from the same return)
--   cells           (department group, budget measure, return) cells compared
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
    (financial_year, method, version, cells, wape, bias, fm_wape, fm_bias, dept_wape, dept_bias, dept_fm_wape, dept_fm_bias)
SELECT b.financial_year, b.method, v.version, COUNT(*),
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
WHERE v.flagged_ok = 1 OR b.is_flagged_return = 0
GROUP BY b.financial_year, b.method, v.version;
GO
