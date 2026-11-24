-- test: in the staged values the main code agrees with the worksheet (sheet number) and with the column (CY or PY), and every provider-year-statement has as many prior-year as current-year values
-- marker: localdata
SELECT CAST(file_id AS varchar(20)) AS detail, source_row, main_code, 'main code does not match the worksheet or the column' AS problem
FROM stg.tac_value
WHERE SUBSTRING(main_code, 2, 2) <> SUBSTRING(worksheet_name, 4, 2)
   OR main_code NOT LIKE 'A[0-9][0-9][CP]Y01'
   OR period_column <> SUBSTRING(main_code, 4, 2)
UNION ALL
SELECT name_key + ' ' + release + ' ' + statement, NULL, NULL, 'current-year and prior-year values are not equal in number'
FROM stg.tac_value
GROUP BY name_key, release, statement
HAVING SUM(CASE WHEN period_column = 'CY' THEN 1 ELSE 0 END) <> SUM(CASE WHEN period_column = 'PY' THEN 1 ELSE 0 END);
