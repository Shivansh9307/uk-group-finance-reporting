-- test: for every return (R13 included), every month and period 0, the loaded rows and the exact amount equal a recomputation from the source files by code that shares nothing with the reader (data/audit/forecast_independent_control.csv): difference 0 in rows and in amount; and dw.forecast_return agrees with it within the four-decimal rounding of its rows
-- marker: localdata
-- requires: raw.forecast_return_cell, raw.forecast_return_expected, dw.forecast_return
SELECT 'loaded differs from the independent recomputation' AS problem,
       COALESCE(l.financial_year, e.financial_year) + ' R' + CAST(COALESCE(l.return_no, e.return_no) AS varchar(10)) + ' P' + CAST(COALESCE(l.period, e.period) AS varchar(10)) AS detail,
       CAST(l.data_rows AS varchar(30)) + ' rows ' + CAST(l.amount AS varchar(60)) + ' vs ' + CAST(e.data_rows AS varchar(30)) + ' rows ' + e.amount_sum AS found
FROM (
    SELECT f.family, f.financial_year, c.return_no, c.period, SUM(CAST(c.source_rows AS bigint)) AS data_rows, SUM(c.amount) AS amount
    FROM raw.forecast_return_cell AS c JOIN raw.forecast_return_file AS f ON f.file_id = c.file_id
    GROUP BY f.family, f.financial_year, c.return_no, c.period
) AS l
FULL OUTER JOIN raw.forecast_return_expected AS e
  ON e.family = l.family AND e.financial_year = l.financial_year AND e.return_no = l.return_no AND e.period = l.period
WHERE l.data_rows IS NULL OR e.data_rows IS NULL OR l.data_rows <> e.data_rows OR l.amount <> CAST(e.amount_sum AS decimal(38, 16))
UNION ALL
SELECT 'dw monthly total differs from the independent recomputation by more than rounding',
       d.financial_year + ' R' + CAST(d.return_no AS varchar(10)) + ' P' + CAST(d.period AS varchar(10)),
       CAST(d.amount AS varchar(60)) + ' vs ' + CAST(e.amount AS varchar(60))
FROM (SELECT financial_year, return_no, period, SUM(amount) AS amount, COUNT_BIG(*) AS n FROM dw.forecast_return GROUP BY financial_year, return_no, period) AS d
JOIN (SELECT financial_year, return_no, period, SUM(CAST(amount_sum AS decimal(38, 16))) AS amount FROM raw.forecast_return_expected GROUP BY financial_year, return_no, period) AS e
  ON e.financial_year = d.financial_year AND e.return_no = d.return_no AND e.period = d.period
LEFT JOIN (SELECT financial_year, return_no, period, SUM(amount_exact) AS amount, COUNT_BIG(*) AS n FROM quarantine.forecast_return_unmapped GROUP BY financial_year, return_no, period) AS q
  ON q.financial_year = d.financial_year AND q.return_no = d.return_no AND q.period = d.period
WHERE ABS(d.amount + COALESCE(q.amount, 0) - e.amount) > 0.00005 * (d.n + COALESCE(q.n, 0));
