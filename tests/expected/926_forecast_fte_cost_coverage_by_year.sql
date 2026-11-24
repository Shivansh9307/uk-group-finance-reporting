-- requires: dw.forecast_accuracy, dw.forecast_pay_accuracy, dw.forecast_fte_cost_input
-- Independent of the model views: the FTE x cost rows and the department rows of the pay-line accuracy table, and the workforce paybill and
-- pay-line month of the FTE x cost input (pounds divided by 1,000 at the boundary).
-- The model's ratios agree with this query to within 0.000001 (the largest difference on these tests in evidence/model/dax_tests.csv is 0.00000099; the comparison tolerance is 0.0001): the SQL carries 10 decimal places, the agreement is to 6.
WITH elig AS (
    SELECT financial_year, COUNT_BIG(*) AS n FROM dw.forecast_pay_accuracy
    WHERE method = 'department' AND return_no BETWEEN 1 AND 11 GROUP BY financial_year
),
cov AS (
    SELECT financial_year, COUNT_BIG(*) AS n FROM dw.forecast_pay_accuracy WHERE method = 'fte_cost' GROUP BY financial_year
),
cvr AS (
    SELECT i.financial_year, SUM(i.workforce_paybill_gbp / 1000) AS wf, SUM(i.pay_month_n) AS pay
    FROM dw.forecast_fte_cost_input AS i
    JOIN dw.forecast_pay_accuracy AS a ON a.financial_year = i.financial_year AND a.return_no = i.return_no
                                      AND a.department_group_code = i.department_group_code AND a.method = 'fte_cost'
    WHERE i.pay_month_n > 0
    GROUP BY i.financial_year
)
SELECT e.financial_year,
       CAST(CAST(c.n AS decimal(38, 10)) / e.n AS decimal(38, 10)) AS cell_coverage,
       CAST(v.wf / v.pay AS decimal(38, 10)) AS pay_cover
FROM elig AS e
JOIN cov AS c ON c.financial_year = e.financial_year
JOIN cvr AS v ON v.financial_year = e.financial_year
WHERE e.financial_year BETWEEN '2018-19' AND '2022-23'
ORDER BY financial_year;
