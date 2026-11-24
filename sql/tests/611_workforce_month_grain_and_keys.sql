-- test: dw.workforce_month has one row per durable organisation, month and measure, every durable key is in dw.dim_organisation, and an organisation has one publisher in a month
-- marker: localdata
-- requires: dw.workforce_month, dw.dim_organisation
SELECT TOP (20) 'duplicate grain' AS problem, durable_key, report_month, measure_key
FROM dw.workforce_month GROUP BY durable_key, month_start, report_month, measure_key HAVING COUNT(*) > 1
UNION ALL
SELECT TOP (20) 'unknown durable key', w.durable_key, w.report_month, w.measure_key
FROM dw.workforce_month AS w
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_organisation AS o WHERE o.durable_key = w.durable_key)
UNION ALL
SELECT TOP (20) 'two publishers', durable_key, report_month, CAST(COUNT(DISTINCT publisher) AS varchar(40))
FROM dw.workforce_month GROUP BY durable_key, report_month HAVING COUNT(DISTINCT publisher) > 1
UNION ALL
SELECT TOP (20) 'month and label disagree', durable_key, report_month, measure_key
FROM dw.workforce_month WHERE report_month <> FORMAT(month_start, 'yyyy-MM') OR DAY(month_start) <> 1;
