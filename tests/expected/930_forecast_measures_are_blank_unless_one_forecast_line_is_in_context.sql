-- requires: dw.forecast_accuracy, dw.forecast_pay_accuracy
-- Independent of the model views: the department's rows of FY2021-22 in the two accuracy tables. The first two cases have no value (NULL):
-- the model returns blank unless exactly one forecast line is in the filter context. The two others are the sums of one table each.
-- The model's ratios agree with this query to within 0.000001 (the largest difference on these tests in evidence/model/dax_tests.csv is 0.00000099; the comparison tolerance is 0.0001): the SQL carries 10 decimal places, the agreement is to 6.
SELECT '1 no line filter' AS [case], CAST(NULL AS bigint) AS cells, CAST(NULL AS decimal(38, 4)) AS abs_error,
       CAST(NULL AS decimal(38, 10)) AS wape, CAST(NULL AS decimal(38, 10)) AS wape_excl
UNION ALL
SELECT '2 both lines in the filter', NULL, NULL, NULL, NULL
UNION ALL
SELECT '3 budget measure total', COUNT_BIG(*), CAST(SUM(full_year_abs_error) AS decimal(38, 4)),
       CAST(SUM(CAST(full_year_abs_error AS decimal(38, 10))) / SUM(CAST(full_year_abs_outturn AS decimal(38, 10))) AS decimal(38, 10)),
       CAST(SUM(CASE WHEN is_flagged_return = 0 THEN CAST(full_year_abs_error AS decimal(38, 10)) END)
            / SUM(CASE WHEN is_flagged_return = 0 THEN CAST(full_year_abs_outturn AS decimal(38, 10)) END) AS decimal(38, 10))
FROM dw.forecast_accuracy WHERE method = 'department' AND financial_year = '2021-22'
UNION ALL
SELECT '4 pay line', COUNT_BIG(*), CAST(SUM(full_year_abs_error) AS decimal(38, 4)),
       CAST(SUM(CAST(full_year_abs_error AS decimal(38, 10))) / SUM(CAST(full_year_abs_outturn AS decimal(38, 10))) AS decimal(38, 10)),
       CAST(SUM(CASE WHEN is_flagged_return = 0 THEN CAST(full_year_abs_error AS decimal(38, 10)) END)
            / SUM(CASE WHEN is_flagged_return = 0 THEN CAST(full_year_abs_outturn AS decimal(38, 10)) END) AS decimal(38, 10))
FROM dw.forecast_pay_accuracy WHERE method = 'department' AND financial_year = '2021-22'
ORDER BY [case];
