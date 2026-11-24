-- test: at return x organisation x economic category x control budget detail x economic budget x month (periods 1 to 12) the load holds exactly 1,419,936 rows for the annual extracts and 703,146 for the MFO files, the counts the profiling gave
-- marker: localdata
-- requires: stg.forecast_return_cell
SELECT e.family, x.n AS rows_loaded, e.expected
FROM (VALUES ('extract', 1419936), ('mfo', 703146)) AS e (family, expected)
LEFT JOIN (
    SELECT family, COUNT(*) AS n
    FROM (SELECT DISTINCT family, financial_year, return_no, organisation_code, economic_category_code, control_budget_detail,
                          economic_budget, period
          FROM stg.forecast_return_cell WHERE period BETWEEN 1 AND 12) AS g
    GROUP BY family
) AS x ON x.family = e.family
WHERE x.n IS NULL OR x.n <> e.expected;
