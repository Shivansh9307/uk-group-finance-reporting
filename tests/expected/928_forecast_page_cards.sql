-- requires: dw.forecast_accuracy, dw.forecast_pay_accuracy, dw.forecast_fte_cost_input
-- Independent of the model views: the department rows of dw.forecast_accuracy, and the FTE x cost rows and department rows of the pay-line table
-- with the workforce paybill (pounds, divided by 1,000) and the pay line of the month from dw.forecast_fte_cost_input. One row for each card.
-- The model's ratios agree with this query to within 0.000001 (the largest difference on these tests in evidence/model/dax_tests.csv is 0.00000099; the comparison tolerance is 0.0001): the SQL carries 10 decimal places, the agreement is to 6.
SELECT 'wape' AS card,
       CAST(SUM(CAST(full_year_abs_error AS decimal(38, 10))) / SUM(CAST(full_year_abs_outturn AS decimal(38, 10))) AS decimal(38, 10)) AS value
FROM dw.forecast_accuracy WHERE method = 'department'
UNION ALL
SELECT 'wape_excl',
       CAST(SUM(CAST(full_year_abs_error AS decimal(38, 10))) / SUM(CAST(full_year_abs_outturn AS decimal(38, 10))) AS decimal(38, 10))
FROM dw.forecast_accuracy WHERE method = 'department' AND is_flagged_return = 0
UNION ALL
SELECT 'flagged_cells', CAST(COUNT_BIG(*) AS decimal(38, 10)) FROM dw.forecast_accuracy WHERE method = 'department' AND is_flagged_return = 1
UNION ALL
SELECT 'cell_coverage',
       CAST(CAST((SELECT COUNT_BIG(*) FROM dw.forecast_pay_accuracy WHERE method = 'fte_cost' AND financial_year >= '2018-19') AS decimal(38, 10))
            / (SELECT COUNT_BIG(*) FROM dw.forecast_pay_accuracy WHERE method = 'department' AND return_no BETWEEN 1 AND 11 AND financial_year >= '2018-19')
            AS decimal(38, 10))
UNION ALL
SELECT 'pay_cover', CAST(SUM(i.workforce_paybill_gbp / 1000) / SUM(i.pay_month_n) AS decimal(38, 10))
FROM dw.forecast_fte_cost_input AS i
JOIN dw.forecast_pay_accuracy AS a ON a.financial_year = i.financial_year AND a.return_no = i.return_no
                                  AND a.department_group_code = i.department_group_code AND a.method = 'fte_cost'
WHERE i.pay_month_n > 0 AND i.financial_year >= '2018-19'
ORDER BY card;
