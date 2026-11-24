-- requires: dw.forecast_accuracy, dw.forecast_pay_accuracy
-- Independent of the model views: the rows of the two accuracy tables, the four methods of the check constraint and R0 to R12.
SELECT N'Fact Forecast Accuracy (derived)' AS table_name,
       (SELECT COUNT_BIG(*) FROM dw.forecast_accuracy) + (SELECT COUNT_BIG(*) FROM dw.forecast_pay_accuracy) AS row_count
UNION ALL SELECT N'Forecast Method', CAST(4 AS bigint)
UNION ALL SELECT N'Forecast Return', COUNT_BIG(DISTINCT return_no) FROM dw.forecast_return_header WHERE return_no BETWEEN 0 AND 12
ORDER BY table_name;
