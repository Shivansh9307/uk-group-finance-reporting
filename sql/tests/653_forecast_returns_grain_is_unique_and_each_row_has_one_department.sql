-- test: dw.forecast_return is unique at return x organisation x economic category x control budget detail x economic budget x period, the cells behind each row agree on one department group and one Spending Review group, and the rows plus the quarantined grain keys equal the grain keys of the staged cells
-- marker: localdata
-- requires: dw.forecast_return, stg.forecast_return_cell, quarantine.forecast_return_unmapped
SELECT 'grain key twice in dw.forecast_return' AS problem,
       financial_year + ' R' + CAST(return_no AS varchar(10)) + ' ' + organisation_code AS detail
FROM dw.forecast_return
GROUP BY financial_year, return_no, period, organisation_code, economic_category_code, control_budget_detail, economic_budget
HAVING COUNT(*) > 1
UNION ALL
SELECT 'cells of one grain key disagree on the department group or Spending Review group',
       c.financial_year + ' R' + CAST(c.return_no AS varchar(10)) + ' ' + c.organisation_code
FROM stg.forecast_return_cell AS c
GROUP BY c.financial_year, c.return_no, c.period, c.organisation_code, c.economic_category_code, c.control_budget_detail, c.economic_budget
HAVING COUNT(DISTINCT c.department_group_code) > 1 OR COUNT(DISTINCT c.sr_group_code) > 1
UNION ALL
SELECT 'dw rows plus quarantined grain keys differ from the grain keys of the cells',
       CAST(a.n AS varchar(20)) + ' + ' + CAST(q.n AS varchar(20)) + ' <> ' + CAST(g.n AS varchar(20))
FROM (SELECT COUNT_BIG(*) AS n FROM dw.forecast_return) AS a
CROSS JOIN (SELECT COUNT_BIG(*) AS n
            FROM (SELECT DISTINCT financial_year, return_no, period, organisation_code, economic_category_code,
                                  control_budget_detail, economic_budget
                  FROM quarantine.forecast_return_unmapped) AS z) AS q
CROSS JOIN (SELECT COUNT_BIG(*) AS n
            FROM (SELECT DISTINCT financial_year, return_no, period, organisation_code, economic_category_code,
                                  control_budget_detail, economic_budget
                  FROM stg.forecast_return_cell) AS z) AS g
WHERE a.n + q.n <> g.n;
