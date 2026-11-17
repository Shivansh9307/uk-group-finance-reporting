-- dw.dim_period: one row per financial year and period 0-12, FY2018-19 to FY2028-29 (plans run to 2028-29).
--   period_key       yyyypp, yyyy = the year the financial year starts in, pp = 00..12 (201800 .. 202812)
--   period           1 = April ... 12 = March; 0 = "not allocated to a month". Period 0 is counted in year
--                    totals and year to date; the source has it only in June 2019 (FY2018-19).
--   month_start_date first day of the calendar month; NULL for period 0
--   fiscal_quarter   1..4, NULL for period 0
--   period_sort      1.. in time order, period 0 first within its year

DROP TABLE IF EXISTS dw.dim_period;
GO

CREATE TABLE dw.dim_period (
    period_key        int          NOT NULL CONSTRAINT pk_dw_dim_period PRIMARY KEY,
    financial_year    varchar(7)   NOT NULL,
    fiscal_year_start smallint     NOT NULL,
    period            tinyint      NOT NULL,
    period_label      varchar(20)  NOT NULL,
    month_name        varchar(30)  NOT NULL,
    month_start_date  date         NULL,
    fiscal_quarter    tinyint      NULL,
    is_period0        bit          NOT NULL,
    period_sort       int          NOT NULL,
    CONSTRAINT uq_dw_dim_period UNIQUE (financial_year, period),
    CONSTRAINT uq_dw_dim_period_sort UNIQUE (period_sort)
);
GO

WITH y AS (
    SELECT TOP (11) 2017 + ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS fy_start FROM sys.all_objects
), p AS (
    SELECT TOP (13) ROW_NUMBER() OVER (ORDER BY (SELECT 1)) - 1 AS period FROM sys.all_objects
)
INSERT INTO dw.dim_period
    (period_key, financial_year, fiscal_year_start, period, period_label, month_name, month_start_date,
     fiscal_quarter, is_period0, period_sort)
SELECT y.fy_start * 100 + p.period,
       CAST(y.fy_start AS varchar(4)) + '-' + RIGHT(CAST(y.fy_start + 1 AS varchar(4)), 2),
       y.fy_start, p.period,
       CAST(CASE WHEN p.period = 0 THEN 'P00 not allocated'
                 ELSE 'P' + RIGHT('0' + CAST(p.period AS varchar(2)), 2) + ' ' + LEFT(DATENAME(month, m.d), 3) END AS varchar(20)),
       CAST(CASE WHEN p.period = 0 THEN 'Not allocated to a month' ELSE DATENAME(month, m.d) END AS varchar(30)),
       CASE WHEN p.period = 0 THEN NULL ELSE m.d END,
       CASE WHEN p.period = 0 THEN NULL ELSE CAST((p.period + 2) / 3 AS tinyint) END,
       CAST(CASE WHEN p.period = 0 THEN 1 ELSE 0 END AS bit),
       CAST(ROW_NUMBER() OVER (ORDER BY y.fy_start, p.period) AS int)
FROM y
CROSS JOIN p
CROSS APPLY (
    SELECT DATEFROMPARTS(y.fy_start + CASE WHEN p.period >= 10 THEN 1 ELSE 0 END,
                         CASE WHEN p.period = 0 THEN 4 WHEN p.period <= 9 THEN p.period + 3 ELSE p.period - 9 END, 1) AS d
) AS m;
GO
