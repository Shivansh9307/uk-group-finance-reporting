-- test: no organisation is both DRAFT and CONFIRMED in one return, every status is one the files use (CONFIRMED and DRAFT in the extracts, Confirmed and Locked in the MFO files), and every control budget name and economic budget is recognised
-- marker: localdata
-- requires: stg.forecast_return_cell
SELECT 'organisation under DRAFT and CONFIRMED in one return' AS problem,
       c.financial_year + ' R' + CAST(c.return_no AS varchar(10)) + ' ' + c.organisation_code AS detail
FROM stg.forecast_return_cell AS c
GROUP BY c.financial_year, c.return_no, c.organisation_code
HAVING MAX(CASE WHEN c.status_code = 'DRAFT' THEN 1 ELSE 0 END) = 1 AND MAX(CASE WHEN c.status_code = 'CONFIRMED' THEN 1 ELSE 0 END) = 1
UNION ALL
SELECT 'status outside the known four', c.family + ' ' + c.status_code
FROM stg.forecast_return_cell AS c
WHERE NOT (c.family = 'extract' AND c.status_code IN ('CONFIRMED', 'DRAFT') OR c.family = 'mfo' AND c.status_code IN ('Confirmed', 'Locked'))
GROUP BY c.family, c.status_code
UNION ALL
SELECT 'control budget name not recognised', c.family + ' ' + CAST(COUNT(*) AS varchar(10)) + ' cells'
FROM stg.forecast_return_cell AS c WHERE c.control_budget_detail IS NULL GROUP BY c.family
UNION ALL
SELECT 'economic budget outside the four known', c.economic_budget
FROM stg.forecast_return_cell AS c WHERE c.economic_budget NOT IN ('RESOURCE', 'CAPITAL', 'n/a', 'OTHER NON-BUDGET') GROUP BY c.economic_budget;
