-- Independent of the model: the actual of the cell in each window (whole year, period 12, periods 10 to 12, the twelve
-- allocated months, the year before) from the outturn fact, then each divided by the unit; YoY % is not scaled.
WITH ac AS (
    SELECT d.financial_year AS fy, d.period, f.amount_delta
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS d ON d.period_key = f.period_key
    JOIN dw.dim_organisation AS o ON o.organisation_key = f.organisation_key
    JOIN dw.dim_account AS a ON a.account_key = f.account_key
    JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = f.control_budget_key
    WHERE o.organisation_code = 'DFE022' AND cb.control_budget_detail_code IN ('DEL PROG', 'DEL ADMIN')
      AND a.economic_budget = 'RESOURCE' AND d.financial_year IN ('2019-20', '2020-21')
), q AS (
    SELECT
        (SELECT SUM(amount_delta) FROM ac WHERE fy = '2020-21') AS a2,
        (SELECT SUM(amount_delta) FROM ac WHERE fy = '2019-20') AS a1,
        (SELECT SUM(amount_delta) FROM ac WHERE fy = '2020-21' AND period = 12) AS a_mtd,
        (SELECT SUM(amount_delta) FROM ac WHERE fy = '2020-21' AND period BETWEEN 10 AND 12) AS a_qtd,
        (SELECT SUM(amount_delta) FROM ac WHERE fy = '2020-21' AND period BETWEEN 1 AND 12) AS a_r12
), units AS (
    SELECT u.label, u.divisor FROM (VALUES (N'GBP k', CAST(1 AS decimal(19, 4))), (N'GBP m', CAST(1000 AS decimal(19, 4))), (N'GBP bn', CAST(1000000 AS decimal(19, 4)))) AS u(label, divisor)
), items AS (
    SELECT units.label AS unit_label, N'Current' AS ti, q.a2 / units.divisor AS value FROM q CROSS JOIN units
    UNION ALL SELECT units.label, N'MTD', q.a_mtd / units.divisor FROM q CROSS JOIN units
    UNION ALL SELECT units.label, N'QTD', q.a_qtd / units.divisor FROM q CROSS JOIN units
    UNION ALL SELECT units.label, N'YTD', q.a2 / units.divisor FROM q CROSS JOIN units
    UNION ALL SELECT units.label, N'PY', q.a1 / units.divisor FROM q CROSS JOIN units
    UNION ALL SELECT units.label, N'YoY', (q.a2 - q.a1) / units.divisor FROM q CROSS JOIN units
    UNION ALL SELECT units.label, N'YoY %', (q.a2 - q.a1) * 1000000 / NULLIF(ABS(q.a1), 0) FROM q CROSS JOIN units
    UNION ALL SELECT units.label, N'Rolling 12 months', q.a_r12 / units.divisor FROM q CROSS JOIN units
)
SELECT unit_label, ti AS [Time Calculation], CAST(value AS decimal(38, 6)) AS value
FROM items
ORDER BY unit_label, ti;
