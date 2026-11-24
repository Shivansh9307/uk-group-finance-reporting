-- scope: full
-- How good the forecasts of the pay line (economic category A101 of RDEL) are, at department group x year x return, for the
-- department's own pay-line forecast and for my three methods (dw.forecast_own_pay: run_rate, seasonal, fte_cost), against the
-- pay line of R13. The same construction and the same columns as dw.forecast_month_compare and dw.forecast_accuracy
-- (sql/dw/670), so every measure reads both alike; budget_measure is always RDEL.
--   A cell is every department group that has a pay line in return n or in R13 of the year; a group missing from return n has no
--   forecast and counts as zero, as in dw.forecast_accuracy. Own methods exist only for the cells that have actual months.
--   is_flagged_return is the flag of dw.forecast_return_quality for the department group in the return (the group's whole return
--   is flagged, not only its pay line).

DROP TABLE IF EXISTS dw.forecast_pay_accuracy;
GO
DROP TABLE IF EXISTS dw.forecast_pay_month_compare;
GO

CREATE TABLE dw.forecast_pay_month_compare (
    financial_year         varchar(7)     NOT NULL,
    return_no              tinyint        NOT NULL,
    department_group_code  nvarchar(50)   NOT NULL,
    budget_measure         varchar(5)     NOT NULL,
    method                 varchar(10)    NOT NULL,   -- department | run_rate | seasonal | fte_cost
    period                 tinyint        NOT NULL,
    forecast_status        varchar(11)    NOT NULL,
    amount_forecast        decimal(19,4)  NOT NULL,
    amount_outturn         decimal(19,4)  NOT NULL,
    CONSTRAINT pk_dw_forecast_pay_month_compare PRIMARY KEY
        (financial_year, return_no, department_group_code, budget_measure, method, period),
    CONSTRAINT ck_dw_forecast_pay_month_compare_method CHECK (method IN ('department', 'run_rate', 'seasonal', 'fte_cost'))
);
GO

WITH months AS (
    SELECT m.period FROM (VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12)) AS m (period)
),
ret AS (
    SELECT r.financial_year, r.return_no, r.department_group_code, r.period, SUM(r.amount) AS amount
    FROM dw.forecast_return AS r
    WHERE r.return_no BETWEEN 0 AND 12 AND r.period BETWEEN 1 AND 12 AND r.budget_measure = 'RDEL' AND r.economic_category_code = 'A101'
    GROUP BY r.financial_year, r.return_no, r.department_group_code, r.period
),
fin AS (
    SELECT r.financial_year, r.department_group_code, r.period, SUM(r.amount) AS amount
    FROM dw.forecast_return AS r
    WHERE r.return_no = 13 AND r.period BETWEEN 1 AND 12 AND r.budget_measure = 'RDEL' AND r.economic_category_code = 'A101'
    GROUP BY r.financial_year, r.department_group_code, r.period
),
cells AS (
    SELECT DISTINCT financial_year, return_no, department_group_code FROM ret
    UNION
    SELECT DISTINCT h.financial_year, h.return_no, f.department_group_code
    FROM fin AS f
    JOIN dw.forecast_return_header AS h ON h.financial_year = f.financial_year AND h.return_no BETWEEN 0 AND 12
)
INSERT INTO dw.forecast_pay_month_compare
    (financial_year, return_no, department_group_code, budget_measure, method, period, forecast_status, amount_forecast, amount_outturn)
SELECT c.financial_year, c.return_no, c.department_group_code, 'RDEL', 'department', mo.period,
       CASE WHEN mo.period < c.return_no THEN 'actual' WHEN mo.period = c.return_no THEN 'provisional' ELSE 'forecast' END,
       COALESCE(r.amount, 0), COALESCE(f.amount, 0)
FROM cells AS c
CROSS JOIN months AS mo
LEFT JOIN ret AS r ON r.financial_year = c.financial_year AND r.return_no = c.return_no
                  AND r.department_group_code = c.department_group_code AND r.period = mo.period
LEFT JOIN fin AS f ON f.financial_year = c.financial_year AND f.department_group_code = c.department_group_code
                  AND f.period = mo.period;
GO

WITH months AS (
    SELECT m.period FROM (VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12)) AS m (period)
),
fin AS (
    SELECT r.financial_year, r.department_group_code, r.period, SUM(r.amount) AS amount
    FROM dw.forecast_return AS r
    WHERE r.return_no = 13 AND r.period BETWEEN 1 AND 12 AND r.budget_measure = 'RDEL' AND r.economic_category_code = 'A101'
    GROUP BY r.financial_year, r.department_group_code, r.period
),
own_cells AS (
    SELECT DISTINCT financial_year, return_no, department_group_code, method FROM dw.forecast_own_pay
)
INSERT INTO dw.forecast_pay_month_compare
    (financial_year, return_no, department_group_code, budget_measure, method, period, forecast_status, amount_forecast, amount_outturn)
SELECT c.financial_year, c.return_no, c.department_group_code, 'RDEL', c.method, mo.period,
       CASE WHEN mo.period < c.return_no THEN 'actual' WHEN mo.period = c.return_no THEN 'provisional' ELSE 'forecast' END,
       CASE WHEN mo.period <= c.return_no THEN COALESCE(i.amount, 0) ELSE o.amount END,
       COALESCE(f.amount, 0)
FROM own_cells AS c
CROSS JOIN months AS mo
LEFT JOIN dw.forecast_pay_input AS i
       ON i.financial_year = c.financial_year AND i.return_no = c.return_no AND i.department_group_code = c.department_group_code
      AND i.period = mo.period
LEFT JOIN dw.forecast_own_pay AS o
       ON o.financial_year = c.financial_year AND o.return_no = c.return_no AND o.department_group_code = c.department_group_code
      AND o.method = c.method AND o.period = mo.period
LEFT JOIN fin AS f ON f.financial_year = c.financial_year AND f.department_group_code = c.department_group_code
                  AND f.period = mo.period;
GO

CREATE TABLE dw.forecast_pay_accuracy (
    financial_year         varchar(7)     NOT NULL,
    return_no              tinyint        NOT NULL,
    department_group_code  nvarchar(50)   NOT NULL,
    department_group_name  nvarchar(400)  NOT NULL,
    budget_measure         varchar(5)     NOT NULL,
    method                 varchar(10)    NOT NULL,
    forecast_months        tinyint        NOT NULL,
    full_year_forecast     decimal(19,4)  NOT NULL,
    full_year_outturn      decimal(19,4)  NOT NULL,
    full_year_error        decimal(19,4)  NOT NULL,
    full_year_abs_error    decimal(19,4)  NOT NULL,
    full_year_abs_outturn  decimal(19,4)  NOT NULL,
    fm_error               decimal(19,4)  NOT NULL,
    fm_abs_error           decimal(19,4)  NOT NULL,
    fm_abs_outturn         decimal(19,4)  NOT NULL,
    wape                   decimal(19,10) NULL,
    bias                   decimal(19,10) NULL,
    fm_wape                decimal(19,10) NULL,
    fm_bias                decimal(19,10) NULL,
    mape                   decimal(19,10) NULL,
    is_flagged_return      bit            NOT NULL,
    CONSTRAINT pk_dw_forecast_pay_accuracy PRIMARY KEY
        (financial_year, return_no, department_group_code, budget_measure, method)
);
GO

INSERT INTO dw.forecast_pay_accuracy
    (financial_year, return_no, department_group_code, department_group_name, budget_measure, method, forecast_months,
     full_year_forecast, full_year_outturn, full_year_error, full_year_abs_error, full_year_abs_outturn, fm_error, fm_abs_error,
     fm_abs_outturn, wape, bias, fm_wape, fm_bias, mape, is_flagged_return)
SELECT a.financial_year, a.return_no, a.department_group_code, COALESCE(n.department_group_name, a.department_group_code),
       a.budget_measure, a.method, CAST(12 - a.return_no AS tinyint),
       a.full_year_forecast, a.full_year_outturn, a.full_year_forecast - a.full_year_outturn,
       ABS(a.full_year_forecast - a.full_year_outturn), ABS(a.full_year_outturn),
       a.fm_error, a.fm_abs_error, a.fm_abs_outturn,
       CASE WHEN a.full_year_outturn <> 0 THEN CAST(ABS(a.full_year_forecast - a.full_year_outturn) AS decimal(30, 10)) / ABS(a.full_year_outturn) END,
       CASE WHEN a.full_year_outturn <> 0 THEN CAST(a.full_year_forecast - a.full_year_outturn AS decimal(30, 10)) / ABS(a.full_year_outturn) END,
       CASE WHEN a.fm_abs_outturn <> 0 THEN CAST(a.fm_abs_error AS decimal(30, 10)) / a.fm_abs_outturn END,
       CASE WHEN a.fm_abs_outturn <> 0 THEN CAST(a.fm_error AS decimal(30, 10)) / a.fm_abs_outturn END,
       CASE WHEN a.full_year_outturn >= 100000 THEN CAST(ABS(a.full_year_forecast - a.full_year_outturn) AS decimal(30, 10)) / a.full_year_outturn END,
       CASE WHEN EXISTS (SELECT 1 FROM dw.forecast_return_quality AS q
                         WHERE q.financial_year = a.financial_year AND q.return_no = a.return_no
                           AND q.department_group_code = a.department_group_code) THEN 1 ELSE 0 END
FROM (
    SELECT m.financial_year, m.return_no, m.department_group_code, m.budget_measure, m.method,
           SUM(m.amount_forecast) AS full_year_forecast, SUM(m.amount_outturn) AS full_year_outturn,
           SUM(CASE WHEN m.period > m.return_no THEN m.amount_forecast - m.amount_outturn ELSE 0 END) AS fm_error,
           SUM(CASE WHEN m.period > m.return_no THEN ABS(m.amount_forecast - m.amount_outturn) ELSE 0 END) AS fm_abs_error,
           SUM(CASE WHEN m.period > m.return_no THEN ABS(m.amount_outturn) ELSE 0 END) AS fm_abs_outturn
    FROM dw.forecast_pay_month_compare AS m
    GROUP BY m.financial_year, m.return_no, m.department_group_code, m.budget_measure, m.method
) AS a
LEFT JOIN (
    SELECT financial_year, department_group_code, MIN(department_group_name) AS department_group_name
    FROM dw.forecast_return WHERE return_no = 13 GROUP BY financial_year, department_group_code
) AS n ON n.financial_year = a.financial_year AND n.department_group_code = a.department_group_code;
GO
