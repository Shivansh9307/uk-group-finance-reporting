-- scope: full
-- My own forecast of the pay line (economic category A101 of RDEL) at department group x year x return, for the months after the
-- return's last actual month, with the same two methods as dw.forecast_own and a third that only the pay line can have:
--   run_rate   the mean of the n actual months of the pay line to date: ytd / n (n = 1 to 11)
--   seasonal   the prior year's R13 pay profile scaled to the year to date, under the same guard as dw.forecast_own (the
--              prior year's months 1 to n have the sign of the year to date and are at least 10% of the absolute prior-year
--              total); none for FY2017-18
--   fte_cost   FTE x cost: for a remaining month, the full-time equivalent of the last actual month times the average cost per
--              full-time equivalent of that month, from the workforce files. Paybill is in pounds; the forecast is in GBP
--              thousands (divided by 1,000 here, at the boundary). The same figure is forecast for every remaining month.
--              Only the workforce of month n, the month return n has just closed, is read (dw.forecast_fte_cost_input): no
--              later month, no earlier month standing in for a missing one. It exists only where audit.forecast_fte_cost_coverage
--              says 'covered'. It is a method for the pay line only and is never added to a department's total.
--              Algebraically full-time equivalent x (paybill / full-time equivalent) is the paybill of month n: I build it as the
--              product, with the average cost kept to 16 decimal places, so the lineage shows both factors.
-- Same columns as dw.forecast_own, plus the workforce lineage (NULL for the two other methods).

DROP TABLE IF EXISTS dw.forecast_own_pay;
GO

CREATE TABLE dw.forecast_own_pay (
    financial_year          varchar(7)     NOT NULL,
    return_no               tinyint        NOT NULL,
    department_group_code   nvarchar(50)   NOT NULL,
    budget_measure          varchar(5)     NOT NULL,   -- RDEL: the pay line is resource DEL
    method                  varchar(10)    NOT NULL,   -- run_rate | seasonal | fte_cost
    period                  tinyint        NOT NULL,   -- the forecast month, return_no + 1 .. 12
    amount                  decimal(19,4)  NOT NULL,   -- GBP thousands
    input_return_no         tinyint        NOT NULL,
    input_max_period        tinyint        NOT NULL,
    input_rows              int            NOT NULL,   -- source rows (run_rate, seasonal) or workforce cells (fte_cost) behind the inputs
    ytd_amount              decimal(19,4)  NOT NULL,
    profile_financial_year  varchar(7)     NULL,
    profile_ytd_amount      decimal(19,4)  NULL,
    profile_year_amount     decimal(19,4)  NULL,
    workforce_month         date           NULL,       -- fte_cost: the month read, always the last actual month of the return
    workforce_fte           decimal(19,4)  NULL,
    workforce_paybill_gbp   decimal(19,4)  NULL,       -- pounds
    cost_per_fte_gbp        decimal(38,16) NULL,       -- pounds per full-time equivalent per month
    CONSTRAINT pk_dw_forecast_own_pay PRIMARY KEY (financial_year, return_no, department_group_code, budget_measure, method, period),
    CONSTRAINT ck_dw_forecast_own_pay_method CHECK (method IN ('run_rate', 'seasonal', 'fte_cost')),
    CONSTRAINT ck_dw_forecast_own_pay_future CHECK (period > return_no AND period <= 12),
    CONSTRAINT ck_dw_forecast_own_pay_known CHECK (input_return_no = return_no AND input_max_period <= return_no)
);
GO

WITH ytd AS (
    SELECT i.financial_year, i.return_no, i.department_group_code, i.budget_measure,
           SUM(i.amount) AS ytd_amount, SUM(i.source_rows) AS input_rows, MAX(i.period) AS input_max_period
    FROM dw.forecast_pay_input AS i
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
    JOIN dw.forecast_pay_prior_profile AS p
      ON p.financial_year = y.financial_year AND p.department_group_code = y.department_group_code
     AND p.budget_measure = y.budget_measure
    GROUP BY y.financial_year, y.return_no, y.department_group_code, y.budget_measure
)
INSERT INTO dw.forecast_own_pay
    (financial_year, return_no, department_group_code, budget_measure, method, period, amount, input_return_no, input_max_period,
     input_rows, ytd_amount, profile_financial_year, profile_ytd_amount, profile_year_amount,
     workforce_month, workforce_fte, workforce_paybill_gbp, cost_per_fte_gbp)
SELECT y.financial_year, y.return_no, y.department_group_code, y.budget_measure, 'run_rate', mo.period,
       CAST(CAST(y.ytd_amount AS decimal(20, 6)) / CAST(y.return_no AS decimal(10, 0)) AS decimal(19, 4)),
       y.return_no, y.input_max_period, y.input_rows, y.ytd_amount, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM ytd AS y
JOIN months AS mo ON mo.period > y.return_no
WHERE y.return_no BETWEEN 1 AND 11
UNION ALL
SELECT y.financial_year, y.return_no, y.department_group_code, y.budget_measure, 'seasonal', mo.period,
       CAST(CAST(y.ytd_amount AS decimal(20, 6)) * CAST(COALESCE(p.amount, 0) AS decimal(20, 6)) / CAST(py.profile_ytd_amount AS decimal(20, 6))
            AS decimal(19, 4)),
       y.return_no, y.input_max_period, y.input_rows, y.ytd_amount, py.profile_financial_year, py.profile_ytd_amount, py.profile_year_amount,
       NULL, NULL, NULL, NULL
FROM ytd AS y
JOIN months AS mo ON mo.period > y.return_no
JOIN prior_ytd AS py ON py.financial_year = y.financial_year AND py.return_no = y.return_no
                    AND py.department_group_code = y.department_group_code AND py.budget_measure = y.budget_measure
                    AND SIGN(py.profile_ytd_amount) = SIGN(y.ytd_amount) AND SIGN(y.ytd_amount) <> 0
                    AND ABS(py.profile_ytd_amount) >= 0.1 * ABS(py.profile_year_amount)
LEFT JOIN dw.forecast_pay_prior_profile AS p
  ON p.financial_year = y.financial_year AND p.department_group_code = y.department_group_code
 AND p.budget_measure = y.budget_measure AND p.period = mo.period
WHERE y.return_no BETWEEN 1 AND 11
UNION ALL
SELECT y.financial_year, y.return_no, y.department_group_code, y.budget_measure, 'fte_cost', mo.period,
       CAST(CAST(f.workforce_fte AS decimal(15, 4))
            * (CAST(f.workforce_paybill_gbp AS decimal(22, 4)) / CAST(f.workforce_fte AS decimal(15, 4))) / 1000 AS decimal(19, 4)),
       y.return_no, y.input_max_period, f.workforce_cells, y.ytd_amount, NULL, NULL, NULL,
       f.month_start, f.workforce_fte, f.workforce_paybill_gbp,
       CAST(f.workforce_paybill_gbp AS decimal(22, 4)) / CAST(f.workforce_fte AS decimal(15, 4))
FROM ytd AS y
JOIN dw.forecast_fte_cost_input AS f
  ON f.financial_year = y.financial_year AND f.return_no = y.return_no AND f.department_group_code = y.department_group_code
JOIN months AS mo ON mo.period > y.return_no
WHERE y.return_no BETWEEN 1 AND 11 AND f.workforce_fte > 0;
GO
