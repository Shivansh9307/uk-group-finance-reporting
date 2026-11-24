-- scope: full
-- My own forecast of the remaining months of each year, made at every point n (return n) from what was known at that
-- point, at department group x budget measure (RDEL, CDEL, AME) x month.
--
-- Information set at point n (the no-leakage rule): the rows of return n (and of no later return) for months 1 to n, as
-- return n states them, plus the final outturn (R13) of the prior financial year. Nothing else is read. dw.forecast_own_input
-- holds exactly the first part (return n, months 1 to n, is_actual = 1) and dw.forecast_prior_profile exactly the second;
-- dw.forecast_own is computed from those two tables and from nothing else, and carries the lineage of what it used.
--
-- Two methods, for the months m = n + 1 .. 12 of return n:
--   run_rate  the mean of the n actual months to date: ytd / n. A month with no row counts as zero. Defined for n = 1 .. 11.
--   seasonal  the prior year's R13 monthly profile scaled to the year to date: ytd x prior(m) / prior(1..n). Defined for
--             n = 1 .. 11 and only where the profile is a safe scale: prior(1..n) has the same sign as ytd and is at least 10%
--             of |the prior year's full R13 total| (the department group and budget measure exist in the prior year's R13, so
--             FY2017-18 has no seasonal forecast: its prior year is not in the files). Without the guard the factor
--             prior(m) / prior(1..n) explodes where the prior year's months 1 to n are near zero or of the opposite sign
--             (diagnosis: tests/diagnostics/seasonal_top_errors.sql). A cell that fails the guard has no seasonal forecast
--             at all; audit.forecast_accuracy_headline reports how many cells and how much value that leaves out.
-- R0 has no actual month, so neither method exists for it; for R12 there is no month left to forecast.
-- A FTE x cost-per-FTE method is not here: it needs the workforce data and a later task adds it.
-- Arithmetic is decimal throughout; the intermediate casts keep the product inside 38 digits (a plain DECIMAL(19,4) product
-- of two amounts would exceed 38 digits and lose scale silently).
--   dw.forecast_own columns: amount = the forecast of the month, GBP thousands DECIMAL(19,4); input_return_no = the return
--   the inputs came from (always return_no); input_max_period = the latest month among the inputs (always <= return_no);
--   input_rows = source rows behind the inputs; ytd_amount = months 1 to n as return n states them; profile_financial_year,
--   profile_ytd_amount, profile_year_amount = the prior year, its months 1 to n and its twelve months (NULL for run_rate).

DROP TABLE IF EXISTS dw.forecast_own;
DROP TABLE IF EXISTS dw.forecast_own_input;
DROP TABLE IF EXISTS dw.forecast_prior_profile;
GO

CREATE TABLE dw.forecast_own_input (
    financial_year         varchar(7)     NOT NULL,
    return_no              tinyint        NOT NULL,
    department_group_code  nvarchar(50)   NOT NULL,
    budget_measure         varchar(5)     NOT NULL,
    period                 tinyint        NOT NULL,
    amount                 decimal(19,4)  NOT NULL,
    source_rows            int            NOT NULL,
    CONSTRAINT pk_dw_forecast_own_input PRIMARY KEY (financial_year, return_no, department_group_code, budget_measure, period),
    CONSTRAINT ck_dw_forecast_own_input_known CHECK (period BETWEEN 1 AND return_no)
);
GO

INSERT INTO dw.forecast_own_input (financial_year, return_no, department_group_code, budget_measure, period, amount, source_rows)
SELECT r.financial_year, r.return_no, r.department_group_code, r.budget_measure, r.period, SUM(r.amount), SUM(r.source_rows)
FROM dw.forecast_return AS r
WHERE r.return_no BETWEEN 1 AND 12 AND r.is_actual = 1 AND r.budget_measure IN ('RDEL', 'CDEL', 'AME')
GROUP BY r.financial_year, r.return_no, r.department_group_code, r.budget_measure, r.period;
GO

CREATE TABLE dw.forecast_prior_profile (
    financial_year          varchar(7)     NOT NULL,   -- the year being forecast
    profile_financial_year  varchar(7)     NOT NULL,   -- the prior year, R13
    department_group_code   nvarchar(50)   NOT NULL,
    budget_measure          varchar(5)     NOT NULL,
    period                  tinyint        NOT NULL,
    amount                  decimal(19,4)  NOT NULL,
    CONSTRAINT pk_dw_forecast_prior_profile PRIMARY KEY (financial_year, department_group_code, budget_measure, period)
);
GO

INSERT INTO dw.forecast_prior_profile (financial_year, profile_financial_year, department_group_code, budget_measure, period, amount)
SELECT cur.financial_year, prev.financial_year, r.department_group_code, r.budget_measure, r.period, SUM(r.amount)
FROM dw.forecast_return_header AS prev
JOIN dw.forecast_return_header AS cur ON cur.year_seq = prev.year_seq + 1 AND cur.return_no = 13
JOIN dw.forecast_return AS r ON r.financial_year = prev.financial_year AND r.return_no = 13
WHERE prev.return_no = 13 AND r.period BETWEEN 1 AND 12 AND r.budget_measure IN ('RDEL', 'CDEL', 'AME')
GROUP BY cur.financial_year, prev.financial_year, r.department_group_code, r.budget_measure, r.period;
GO

CREATE TABLE dw.forecast_own (
    financial_year          varchar(7)     NOT NULL,
    return_no               tinyint        NOT NULL,
    department_group_code   nvarchar(50)   NOT NULL,
    budget_measure          varchar(5)     NOT NULL,
    method                  varchar(10)    NOT NULL,   -- run_rate | seasonal
    period                  tinyint        NOT NULL,   -- the forecast month, return_no + 1 .. 12
    amount                  decimal(19,4)  NOT NULL,
    input_return_no         tinyint        NOT NULL,
    input_max_period        tinyint        NOT NULL,
    input_rows              int            NOT NULL,
    ytd_amount              decimal(19,4)  NOT NULL,
    profile_financial_year  varchar(7)     NULL,
    profile_ytd_amount      decimal(19,4)  NULL,
    profile_year_amount     decimal(19,4)  NULL,
    CONSTRAINT pk_dw_forecast_own PRIMARY KEY (financial_year, return_no, department_group_code, budget_measure, method, period),
    CONSTRAINT ck_dw_forecast_own_method CHECK (method IN ('run_rate', 'seasonal')),
    CONSTRAINT ck_dw_forecast_own_future CHECK (period > return_no AND period <= 12),
    CONSTRAINT ck_dw_forecast_own_known CHECK (input_return_no = return_no AND input_max_period <= return_no)
);
GO

WITH ytd AS (
    SELECT i.financial_year, i.return_no, i.department_group_code, i.budget_measure,
           SUM(i.amount) AS ytd_amount, SUM(i.source_rows) AS input_rows, MAX(i.period) AS input_max_period
    FROM dw.forecast_own_input AS i
    GROUP BY i.financial_year, i.return_no, i.department_group_code, i.budget_measure
),
months AS (
    SELECT m.period FROM (VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12)) AS m (period)
),
prior_ytd AS (
    SELECT y.financial_year, y.return_no, y.department_group_code, y.budget_measure,
           MIN(p.profile_financial_year) AS profile_financial_year,
           SUM(CASE WHEN p.period <= y.return_no THEN p.amount ELSE 0 END) AS profile_ytd_amount,
           SUM(p.amount) AS profile_year_amount
    FROM ytd AS y
    JOIN dw.forecast_prior_profile AS p
      ON p.financial_year = y.financial_year AND p.department_group_code = y.department_group_code
     AND p.budget_measure = y.budget_measure
    GROUP BY y.financial_year, y.return_no, y.department_group_code, y.budget_measure
)
INSERT INTO dw.forecast_own
    (financial_year, return_no, department_group_code, budget_measure, method, period, amount, input_return_no,
     input_max_period, input_rows, ytd_amount, profile_financial_year, profile_ytd_amount, profile_year_amount)
SELECT y.financial_year, y.return_no, y.department_group_code, y.budget_measure, 'run_rate', mo.period,
       CAST(CAST(y.ytd_amount AS decimal(20, 6)) / CAST(y.return_no AS decimal(10, 0)) AS decimal(19, 4)),
       y.return_no, y.input_max_period, y.input_rows, y.ytd_amount, NULL, NULL, NULL
FROM ytd AS y
JOIN months AS mo ON mo.period > y.return_no
UNION ALL
SELECT y.financial_year, y.return_no, y.department_group_code, y.budget_measure, 'seasonal', mo.period,
       CAST(CAST(y.ytd_amount AS decimal(20, 6)) * CAST(COALESCE(p.amount, 0) AS decimal(20, 6)) / CAST(py.profile_ytd_amount AS decimal(20, 6))
            AS decimal(19, 4)),
       y.return_no, y.input_max_period, y.input_rows, y.ytd_amount, py.profile_financial_year, py.profile_ytd_amount, py.profile_year_amount
FROM ytd AS y
JOIN months AS mo ON mo.period > y.return_no
JOIN prior_ytd AS py ON py.financial_year = y.financial_year AND py.return_no = y.return_no
                    AND py.department_group_code = y.department_group_code AND py.budget_measure = y.budget_measure
                    AND SIGN(py.profile_ytd_amount) = SIGN(y.ytd_amount) AND SIGN(y.ytd_amount) <> 0
                    AND ABS(py.profile_ytd_amount) >= 0.1 * ABS(py.profile_year_amount)
LEFT JOIN dw.forecast_prior_profile AS p
  ON p.financial_year = y.financial_year AND p.department_group_code = y.department_group_code
 AND p.budget_measure = y.budget_measure AND p.period = mo.period;
GO
