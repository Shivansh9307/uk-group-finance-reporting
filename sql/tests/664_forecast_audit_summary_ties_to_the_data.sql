-- test: audit.forecast_return_summary has one row per year, its R13 control differences are zero in rows and in amount for every year (and zero in amount for every return), its counts equal the header and the quality table, and audit.forecast_accuracy_headline has both versions for every year and method that has accuracy rows
-- marker: localdata
-- requires: audit.forecast_return_summary, audit.forecast_accuracy_headline, dw.forecast_return_header, dw.forecast_return_quality
SELECT 'summary does not have the six years' AS problem, CAST(COUNT(*) AS varchar(10)) AS detail FROM audit.forecast_return_summary HAVING COUNT(*) <> 6
UNION ALL
SELECT 'R13 or return control difference is not zero', financial_year + ' rows ' + CAST(r13_control_rows_diff AS varchar(20)) + ' R13 amount '
       + CAST(r13_control_amount_diff AS varchar(60)) + ' all returns ' + CAST(all_returns_control_amount_diff AS varchar(60))
FROM audit.forecast_return_summary AS s
WHERE r13_control_rows_diff <> 0 OR r13_control_amount_diff <> 0 OR all_returns_control_amount_diff <> 0
UNION ALL
SELECT 'summary count differs from the header or the quality table', s.financial_year
FROM audit.forecast_return_summary AS s
JOIN (SELECT financial_year, COUNT(*) AS returns, SUM(rows_periods_1_12) AS rows_1_12, SUM(rows_period_0) AS rows_0, SUM(quarantined_cells) AS q
      FROM dw.forecast_return_header GROUP BY financial_year) AS h ON h.financial_year = s.financial_year
WHERE s.returns <> h.returns OR s.rows_periods_1_12 <> h.rows_1_12 OR s.rows_period_0 <> h.rows_0 OR s.quarantined_cells <> h.q
   OR s.flagged_rows <> (SELECT COUNT(*) FROM dw.forecast_return_quality AS q WHERE q.financial_year = s.financial_year)
   OR s.flagged_returns <> (SELECT COUNT(DISTINCT q.return_no) FROM dw.forecast_return_quality AS q WHERE q.financial_year = s.financial_year)
UNION ALL
SELECT 'R13 total in dw differs from the exact total by more than rounding', s.financial_year
FROM audit.forecast_return_summary AS s
WHERE ABS(s.r13_total_dw - s.r13_total_exact) > 0.00005 * (SELECT COUNT(*) FROM dw.forecast_return AS r WHERE r.financial_year = s.financial_year AND r.return_no = 13 AND r.period BETWEEN 1 AND 12)
  AND s.quarantined_cells = 0
UNION ALL
SELECT 'headline lacks a version', a.financial_year + ' ' + a.method
FROM (SELECT DISTINCT financial_year, method FROM dw.forecast_accuracy WHERE return_no BETWEEN 1 AND 11) AS a
WHERE (SELECT COUNT(*) FROM audit.forecast_accuracy_headline AS h WHERE h.financial_year = a.financial_year AND h.method = a.method) <> 2;
