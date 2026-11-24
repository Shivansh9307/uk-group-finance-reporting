-- scope: full
-- The views the semantic model reads for forecast accuracy (part 9 of the model's view layer).
--   dw.v_model_forecast_accuracy  one row per forecast line, department group, budget measure, financial year, return and method:
--                                 the scored cells of dw.forecast_accuracy (the three methods on a budget measure total) and of
--                                 dw.forecast_pay_accuracy (the four methods on the pay line)
--   dw.v_model_forecast_method    the four methods, with their definition
--   dw.v_model_forecast_return    the returns that are scored (R0 to R12; R13 is the outturn they are scored against)
-- DERIVED from real data: the department's own forecasts are real returns; the three methods of mine and the scores are
-- computed from them (sql/dw/660, 670 and sql/audit/920 to 922). Nothing is authored or synthetic. Amounts are GBP thousands.
--
--   forecast_line      Total (a budget measure's whole total: RDEL, CDEL or AME) or Pay (the pay line A101 of RDEL), and its name
--   known_bad_return   1 where the department group's whole return is flagged in dw.forecast_return_quality (a units error, a
--                      scale outlier, an organisation missing from the final, a department group missing or nearly missing)
--   common_cells       1 where the cell has a score from every method of its line in that return (three methods on a total,
--                      four on the pay line): the cells on which the methods can be compared like for like
--   mape_*             set only where the full-year outturn is positive and at least GBP 100m (the rule of the accuracy table),
--                      so a pooled MAPE is a ratio of sums over those cells only
--   cover_*            on the FTE x cost rows only: the workforce paybill of the last actual month (GBP thousands) and the pay
--                      line of that month in the return, to show how much of the pay line the method sees (ratio of sums)
--   department_key     the department of the current structure that the group's department number maps to (-1: none; no
--                      group in the accuracy tables has none)

DROP VIEW IF EXISTS dw.v_model_forecast_accuracy;
GO
DROP VIEW IF EXISTS dw.v_model_forecast_method;
GO
DROP VIEW IF EXISTS dw.v_model_forecast_return;
GO

CREATE VIEW dw.v_model_forecast_accuracy
AS
WITH u AS (
    SELECT CAST('Total' AS varchar(5)) AS forecast_line, a.* FROM dw.forecast_accuracy AS a
    UNION ALL
    SELECT CAST('Pay' AS varchar(5)), a.* FROM dw.forecast_pay_accuracy AS a
),
n AS (
    SELECT financial_year, return_no, department_group_code, budget_measure, forecast_line,
           COUNT(DISTINCT method) AS methods_scored
    FROM u
    GROUP BY financial_year, return_no, department_group_code, budget_measure, forecast_line
),
latest AS (   -- the name of the group in the latest year it has a return
    SELECT department_group_code, MIN(department_group_name) AS department_group_name
    FROM dw.forecast_return AS r
    WHERE return_no = 13 AND financial_year = (SELECT MAX(financial_year) FROM dw.forecast_return AS x
                                               WHERE x.department_group_code = r.department_group_code AND x.return_no = 13)
    GROUP BY department_group_code
)
SELECT CAST(u.forecast_line AS varchar(5)) AS forecast_line,
       CAST(CASE u.forecast_line WHEN 'Pay' THEN N'Pay line (A101, resource DEL)' ELSE N'Budget measure total' END AS nvarchar(40)) AS forecast_line_name,
       u.financial_year, CAST(u.return_no AS int) AS return_no, u.department_group_code,
       CAST(l.department_group_name AS nvarchar(400)) AS department_group_name,
       u.budget_measure, u.method,
       g.department_key,
       CAST(u.is_flagged_return AS bit) AS known_bad_return,
       CAST(CASE WHEN n.methods_scored = CASE u.forecast_line WHEN 'Pay' THEN 4 ELSE 3 END THEN 1 ELSE 0 END AS bit) AS common_cells,
       u.full_year_forecast, u.full_year_outturn, u.full_year_error, u.full_year_abs_error, u.full_year_abs_outturn,
       u.fm_error, u.fm_abs_error, u.fm_abs_outturn,
       CAST(CASE WHEN u.mape IS NOT NULL THEN u.full_year_abs_error END AS decimal(19, 4)) AS mape_abs_error,
       CAST(CASE WHEN u.mape IS NOT NULL THEN u.full_year_outturn END AS decimal(19, 4)) AS mape_outturn,
       CAST(CASE WHEN u.method = 'fte_cost' AND c.pay_month_n > 0 THEN c.workforce_paybill_gbp / 1000 END AS decimal(19, 4)) AS cover_workforce,
       CAST(CASE WHEN u.method = 'fte_cost' AND c.pay_month_n > 0 THEN c.pay_month_n END AS decimal(19, 4)) AS cover_pay
FROM u
JOIN n ON n.financial_year = u.financial_year AND n.return_no = u.return_no AND n.department_group_code = u.department_group_code
      AND n.budget_measure = u.budget_measure AND n.forecast_line = u.forecast_line
JOIN dw.forecast_group_department AS g ON g.department_group_code = u.department_group_code
LEFT JOIN latest AS l ON l.department_group_code = u.department_group_code
LEFT JOIN audit.forecast_fte_cost_coverage AS c
       ON c.financial_year = u.financial_year AND c.return_no = u.return_no AND c.department_group_code = u.department_group_code
      AND c.status = 'covered';
GO

CREATE VIEW dw.v_model_forecast_method
AS
SELECT CAST(m.method AS varchar(10)) AS method, CAST(m.method_name AS nvarchar(20)) AS method_name,
       CAST(m.sort_order AS int) AS sort_order, CAST(m.definition AS nvarchar(600)) AS definition
FROM (VALUES
    ('department', N'Department', 1, N'The department''s own forecast of the remaining months, as the return states it (real data).'),
    ('run_rate', N'Run rate', 2, N'My forecast: the mean of the actual months to date, repeated for each remaining month.'),
    ('seasonal', N'Seasonal', 3, N'My forecast: the prior year''s final monthly profile scaled to the year to date; none where the prior year''s months to date are under a tenth of its year or of the opposite sign.'),
    ('fte_cost', N'FTE x cost', 4, N'My forecast, pay line only: the full-time equivalent of the last actual month times its average cost per full-time equivalent, from the workforce files, repeated for each remaining month; only where the department''s workforce is published for that month.')
) AS m (method, method_name, sort_order, definition);
GO

CREATE VIEW dw.v_model_forecast_return
AS
SELECT CAST(r.return_no AS int) AS return_no,
       CAST(CONCAT('R', r.return_no) AS varchar(4)) AS return_label,
       CAST(CASE WHEN r.return_no = 0 THEN N'Before the year: no month is actual'
                 WHEN r.return_no = 12 THEN N'Twelve months actual: no month left to forecast'
                 ELSE CONCAT(N'Months 1 to ', r.return_no, N' actual, ', 12 - r.return_no, N' forecast') END AS nvarchar(80)) AS months_note
FROM (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12)) AS r (return_no);
GO
