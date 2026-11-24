-- test: in a month, the rows behind one organisation and measure are one row of the organisation itself plus rows the map marks as agencies counted in it
-- marker: localdata
-- requires: dw.workforce_month
SELECT TOP (20) durable_key, report_month, measure_key, source_rows, rolled_up_rows
FROM dw.workforce_month
WHERE source_rows - rolled_up_rows > 1 OR rolled_up_rows > source_rows;
