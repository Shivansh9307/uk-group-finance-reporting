-- The ten seasonal cells (department group x budget measure x return) with the largest absolute full-year error, with the
-- numbers that explain them: the year to date, the prior year's months 1 to n (profile_ytd), the prior year's full total, and the
-- share of the second in the third. Run it with `sqlcmd -d <database> -i` against a full-scope build; the CSV beside it is the
-- result before the guard in sql/dw/660 was added.
SET NOCOUNT ON;
SELECT TOP (10) a.financial_year, a.return_no, a.department_group_code, a.budget_measure, o.ytd_amount, o.profile_ytd_amount,
       CAST(a.full_year_forecast AS decimal(19,0)) forecast, CAST(a.full_year_outturn AS decimal(19,0)) r13,
       CAST(a.full_year_abs_error AS decimal(19,0)) abs_err,
       CAST(py.prior_year_total AS decimal(19,0)) prior_year_total,
       CAST(ABS(o.profile_ytd_amount) / NULLIF(ABS(py.prior_year_total),0) AS decimal(9,4)) profile_share
FROM dw.forecast_accuracy a
CROSS APPLY (SELECT TOP (1) ytd_amount, profile_ytd_amount, profile_financial_year FROM dw.forecast_own o
             WHERE o.financial_year=a.financial_year AND o.return_no=a.return_no AND o.department_group_code=a.department_group_code
               AND o.budget_measure=a.budget_measure AND o.method='seasonal') o
CROSS APPLY (SELECT SUM(amount) prior_year_total FROM dw.forecast_prior_profile p WHERE p.financial_year=a.financial_year
             AND p.department_group_code=a.department_group_code AND p.budget_measure=a.budget_measure) py
WHERE a.method='seasonal' ORDER BY a.full_year_abs_error DESC;
