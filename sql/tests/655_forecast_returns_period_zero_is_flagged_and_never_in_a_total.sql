-- test: period 0 (budget adjustments) is kept and flagged, exists only in R13 of the annual extracts, is never in a return's total (dw.forecast_return_header), and never reaches the own-forecast inputs, the profile, the month comparison or the accuracy
-- marker: localdata
-- requires: dw.forecast_return, dw.forecast_return_header, dw.forecast_own_input, dw.forecast_prior_profile, dw.forecast_month_compare
SELECT 'period 0 outside R13 of the extracts' AS problem, r.financial_year + ' R' + CAST(r.return_no AS varchar(10)) AS detail
FROM dw.forecast_return AS r
JOIN dw.forecast_return_header AS h ON h.financial_year = r.financial_year AND h.return_no = r.return_no
WHERE r.period = 0 AND (r.return_no <> 13 OR h.family <> 'extract')
GROUP BY r.financial_year, r.return_no
UNION ALL
SELECT 'period 0 row not flagged, or a flagged row not at period 0', CAST(COUNT(*) AS varchar(20))
FROM dw.forecast_return AS r
WHERE (CASE WHEN r.period = 0 THEN 1 ELSE 0 END) <> r.is_period_zero OR (CASE WHEN r.period = 0 THEN 1 ELSE 0 END) <> (CASE WHEN r.forecast_status = 'adjustment' THEN 1 ELSE 0 END)
HAVING COUNT(*) > 0
UNION ALL
SELECT 'return total differs from periods 1 to 12 of its rows', h.financial_year + ' R' + CAST(h.return_no AS varchar(10))
FROM dw.forecast_return_header AS h
LEFT JOIN (SELECT financial_year, return_no, SUM(amount) AS a FROM dw.forecast_return WHERE period BETWEEN 1 AND 12 GROUP BY financial_year, return_no) AS r
       ON r.financial_year = h.financial_year AND r.return_no = h.return_no
WHERE h.total_periods_1_12 <> COALESCE(r.a, 0)
UNION ALL
SELECT 'period 0 in a derived table', 'forecast_own_input'
FROM dw.forecast_own_input WHERE period NOT BETWEEN 1 AND 12 GROUP BY period
UNION ALL
SELECT 'period 0 in a derived table', 'forecast_prior_profile'
FROM dw.forecast_prior_profile WHERE period NOT BETWEEN 1 AND 12 GROUP BY period
UNION ALL
SELECT 'period 0 in a derived table', 'forecast_month_compare'
FROM dw.forecast_month_compare WHERE period NOT BETWEEN 1 AND 12 GROUP BY period
UNION ALL
SELECT 'month comparison cell without twelve months', m.financial_year + ' R' + CAST(m.return_no AS varchar(10)) + ' ' + m.department_group_code + ' ' + m.budget_measure + ' ' + m.method
FROM dw.forecast_month_compare AS m
GROUP BY m.financial_year, m.return_no, m.department_group_code, m.budget_measure, m.method
HAVING COUNT(*) <> 12;
