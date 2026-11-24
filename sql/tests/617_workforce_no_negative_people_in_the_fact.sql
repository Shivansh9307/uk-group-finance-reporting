-- test: no headcount or full-time equivalent in dw.workforce_month is negative (negative paybill and cost cells exist in the source, as credits and corrections, and are kept; they are counted in docs/data-dictionary/workforce.md)
-- marker: localdata
-- requires: dw.workforce_month, dw.dim_workforce_measure
SELECT TOP (20) w.durable_key, w.report_month, w.measure_key, w.value
FROM dw.workforce_month AS w
JOIN dw.dim_workforce_measure AS m ON m.measure_key = w.measure_key
WHERE m.unit = 'people' AND w.value < 0;
