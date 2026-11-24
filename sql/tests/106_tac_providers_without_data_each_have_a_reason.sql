-- test: a provider that is listed and has no statements in a year has a reason the source gives (accounts not adopted in time, or acquired before the year); none is left without a reason, and the status is reported exactly when the file has the data
-- marker: localdata
SELECT p.provider_code, y.release, y.list_status, 'listed without data and without a reason' AS problem
FROM dw.tac_provider_year AS y
JOIN dw.tac_provider AS p ON p.provider_key = y.provider_key
WHERE y.has_statement_data = 0 AND y.list_status = 'listed_without_data'
UNION ALL
SELECT p.provider_code, y.release, y.list_status, 'status is not reported but the file has the data, or the reverse'
FROM dw.tac_provider_year AS y
JOIN dw.tac_provider AS p ON p.provider_key = y.provider_key
WHERE y.has_statement_data <> CASE WHEN y.list_status = 'reported' THEN 1 ELSE 0 END
UNION ALL
SELECT p.provider_code, y.release, y.list_status, 'excluded or acquired without the source saying so'
FROM dw.tac_provider_year AS y
JOIN dw.tac_provider AS p ON p.provider_key = y.provider_key
WHERE (y.list_status = 'excluded' AND y.source_comment NOT LIKE N'%is excluded from this dataset%')
   OR (y.list_status = 'acquired' AND y.source_comment NOT LIKE N'%there is no 20__/__ data%');
