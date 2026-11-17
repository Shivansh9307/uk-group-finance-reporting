-- Typed in-year rows, one per release x line x month, zero-amount rows dropped.
--   financial_year and period come from the Month text, never from Year or Quarter:
--     'Apr-22' -> 2022-23, period 1 ... 'Mar-23' -> 2022-23, period 12;
--     'Period 0 - 18-19' -> 2018-19, period 0 (June 2019 only: not allocated to a month).
--   fiscal_quarter = (period + 2) / 3; NULL for period 0. The Quarter column is wrong on every row
--   of September 2022, so it is not used.
--   amount is DECIMAL(19,4): the exact value (whole + frac) rounded half away from zero, which is
--   what the control total amount_sum_rounded_4dp is built with.
-- Rows are read from raw.oscar_inyear only; the loader has already moved unreadable rows to quarantine.

DROP TABLE IF EXISTS stg.inyear_snapshot;
GO

CREATE TABLE stg.inyear_snapshot (
    release                      varchar(7)    NOT NULL,
    organisation_code            nvarchar(50)  NOT NULL,
    sub_segment_code             nvarchar(50)  NOT NULL,
    economic_category_code       nvarchar(50)  NOT NULL,
    control_budget_detail_code   nvarchar(100) NOT NULL,
    period                       tinyint       NOT NULL,   -- 0 = not allocated to a month, 1 = April ... 12 = March
    financial_year               varchar(7)    NOT NULL,   -- '2022-23'
    fiscal_quarter               tinyint       NULL,       -- 1..4, NULL for period 0
    control_budget_code          nvarchar(100) NOT NULL,   -- as published (TOTAL DEL from December 2022)
    economic_budget_code         nvarchar(100) NOT NULL,
    pesa_economic_group_code     nvarchar(400) NOT NULL,
    amount                       decimal(19,4) NOT NULL,   -- GBP thousands; spending positive, income negative
    file_id                      int           NOT NULL,   -- lineage to raw.oscar_inyear
    source_row                   int           NOT NULL,
    CONSTRAINT pk_stg_inyear_snapshot PRIMARY KEY CLUSTERED
        (release, organisation_code, sub_segment_code, economic_category_code, control_budget_detail_code, period)
);
GO

INSERT INTO stg.inyear_snapshot WITH (TABLOCK)
    (release, organisation_code, sub_segment_code, economic_category_code, control_budget_detail_code,
     period, financial_year, fiscal_quarter, control_budget_code, economic_budget_code,
     pesa_economic_group_code, amount, file_id, source_row)
SELECT
    t.release, t.organisation_code, t.sub_segment_code, t.economic_category_code, t.control_budget_detail_code,
    t.period, t.financial_year,
    CASE WHEN t.period = 0 THEN NULL ELSE (t.period + 2) / 3 END,
    t.control_budget_code, t.economic_budget_code, t.pesa_economic_group_code,
    t.amount, t.file_id, t.source_row
FROM (
    SELECT
        r.release, r.organisation_code, r.sub_segment_code, r.economic_category_code,
        r.control_budget_detail_code, r.control_budget_code, r.economic_budget_code,
        r.pesa_economic_group_code, r.file_id, r.source_row,
        r.amount_whole, r.amount_frac,
        CAST(CASE WHEN p.is_period0 = 1 THEN 0
                  WHEN p.cal_month >= 4 THEN p.cal_month - 3
                  ELSE p.cal_month + 9 END AS tinyint) AS period,
        CAST(CASE WHEN p.is_period0 = 1
                  THEN '20' + SUBSTRING(r.[month], 12, 2) + '-' + SUBSTRING(r.[month], 15, 2)
                  ELSE CAST(p.fy_start AS varchar(4)) + '-' + RIGHT(CAST(p.fy_start + 1 AS varchar(4)), 2)
             END AS varchar(7)) AS financial_year,
        CAST(r.amount_whole AS decimal(19,4)) + CAST(r.amount_frac AS decimal(19,4)) AS amount
    FROM raw.oscar_inyear AS r
    CROSS APPLY (
        SELECT
            CASE WHEN r.[month] LIKE 'Period 0 - [0-9][0-9]-[0-9][0-9]' THEN 1 ELSE 0 END AS is_period0,
            CASE LEFT(r.[month], 3)
                 WHEN 'Jan' THEN 1 WHEN 'Feb' THEN 2 WHEN 'Mar' THEN 3 WHEN 'Apr' THEN 4
                 WHEN 'May' THEN 5 WHEN 'Jun' THEN 6 WHEN 'Jul' THEN 7 WHEN 'Aug' THEN 8
                 WHEN 'Sep' THEN 9 WHEN 'Oct' THEN 10 WHEN 'Nov' THEN 11 WHEN 'Dec' THEN 12 END AS cal_month
    ) AS m
    CROSS APPLY (
        SELECT m.is_period0, m.cal_month,
               CASE WHEN r.[month] LIKE '[A-Za-z][A-Za-z][A-Za-z]-[0-9][0-9]'
                    THEN 2000 + CAST(RIGHT(r.[month], 2) AS int) - CASE WHEN m.cal_month >= 4 THEN 0 ELSE 1 END
               END AS fy_start
    ) AS p
    WHERE NOT (r.amount_whole = 0 AND r.amount_frac = 0)
) AS t
ORDER BY t.release, t.organisation_code, t.sub_segment_code, t.economic_category_code,
         t.control_budget_detail_code, t.period;
GO
