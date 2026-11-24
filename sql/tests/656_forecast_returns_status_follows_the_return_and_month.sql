-- test: the status of every row follows the rule from its return number n and month m: actual when m < n, provisional when m = n (n from 1 to 12), forecast when m > n, adjustment at period 0; is_actual is m <= n for months 1 to 12; R0 is all forecast and R13 all actual; every return has all twelve months
-- requires: dw.forecast_return
SELECT 'status does not follow the rule' AS problem, financial_year + ' R' + CAST(return_no AS varchar(10)) + ' P' + CAST(period AS varchar(10)) + ' ' + forecast_status AS detail
FROM dw.forecast_return
WHERE forecast_status <> CASE WHEN period = 0 THEN 'adjustment' WHEN period < return_no THEN 'actual' WHEN period = return_no THEN 'provisional' ELSE 'forecast' END
   OR is_actual <> CASE WHEN period BETWEEN 1 AND 12 AND period <= return_no THEN 1 ELSE 0 END
   OR is_provisional <> CASE WHEN period = return_no AND return_no BETWEEN 1 AND 12 THEN 1 ELSE 0 END
GROUP BY financial_year, return_no, period, forecast_status
UNION ALL
SELECT 'R0 has an actual month', financial_year FROM dw.forecast_return WHERE return_no = 0 AND is_actual = 1 GROUP BY financial_year
UNION ALL
SELECT 'R13 has a forecast or provisional month', financial_year FROM dw.forecast_return
WHERE return_no = 13 AND forecast_status IN ('forecast', 'provisional') GROUP BY financial_year
UNION ALL
SELECT 'a return does not have twelve months', financial_year + ' R' + CAST(return_no AS varchar(10)) FROM dw.forecast_return_header
WHERE months_present <> 12;
