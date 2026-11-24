-- test: dw.forecast_return_quality is exactly what its rules give on dw.forecast_return (recomputed here), never flags R13, catches the two known bad returns (FCDO R0 of FY2020-21 keyed in pounds, the Department of Health missing from R1 of FY2018-19), and every flagged department group is marked in dw.forecast_accuracy
-- requires: dw.forecast_return_quality, dw.forecast_return, dw.forecast_accuracy, dw.forecast_return_header
WITH og AS (
    SELECT financial_year, return_no, organisation_code, MIN(department_group_code) AS dgc, SUM(ABS(amount)) AS gross
    FROM dw.forecast_return
    WHERE period BETWEEN 1 AND 12 AND budget_measure IN ('RDEL', 'CDEL', 'AME')
    GROUP BY financial_year, return_no, organisation_code
),
gg AS (
    SELECT financial_year, return_no, department_group_code AS dgc, SUM(ABS(amount)) AS gross
    FROM dw.forecast_return
    WHERE period BETWEEN 1 AND 12 AND budget_measure IN ('RDEL', 'CDEL', 'AME')
    GROUP BY financial_year, return_no, department_group_code
),
expected AS (
    SELECT o.financial_year, o.return_no,
           CASE WHEN f.gross IS NULL OR f.gross = 0 THEN 'x' WHEN o.gross / f.gross BETWEEN 500 AND 2000 THEN 'u' WHEN o.gross / f.gross >= 20 THEN 's' END AS rule_code,
           o.dgc AS department_group_code, o.organisation_code
    FROM og AS o
    LEFT JOIN og AS f ON f.financial_year = o.financial_year AND f.return_no = 13 AND f.organisation_code = o.organisation_code
    WHERE o.return_no <= 12 AND o.gross >= 1000000
    UNION ALL
    SELECT h.financial_year, h.return_no, CASE WHEN COALESCE(g.gross, 0) = 0 THEN 'm' ELSE 'p' END, f.dgc, N''
    FROM gg AS f
    JOIN dw.forecast_return_header AS h ON h.financial_year = f.financial_year AND h.return_no <= 12
    LEFT JOIN gg AS g ON g.financial_year = f.financial_year AND g.return_no = h.return_no AND g.dgc = f.dgc
    WHERE f.return_no = 13 AND f.gross >= 1000000 AND COALESCE(g.gross, 0) < 0.1 * f.gross
)
SELECT 'flag differs from the rules recomputed' AS problem,
       COALESCE(e.financial_year, q.financial_year) + ' R' + CAST(COALESCE(e.return_no, q.return_no) AS varchar(10)) + ' '
         + COALESCE(e.rule_code, q.rule_code) + ' ' + COALESCE(e.department_group_code, q.department_group_code) + ' '
         + COALESCE(e.organisation_code, q.organisation_code) AS detail
FROM expected AS e
FULL OUTER JOIN dw.forecast_return_quality AS q
  ON q.financial_year = e.financial_year AND q.return_no = e.return_no AND q.rule_code = e.rule_code
 AND q.department_group_code = e.department_group_code AND q.organisation_code = e.organisation_code
WHERE (e.rule_code IS NOT NULL AND q.rule_code IS NULL) OR (q.rule_code IS NOT NULL AND e.rule_code IS NULL)
UNION ALL
SELECT 'R13 is flagged', financial_year FROM dw.forecast_return_quality WHERE return_no = 13 GROUP BY financial_year
UNION ALL
SELECT 'flag without positive amount affected or without evidence', financial_year + ' R' + CAST(return_no AS varchar(10)) + ' ' + rule_code
FROM dw.forecast_return_quality WHERE amount_affected <= 0 OR LEN(evidence) = 0
UNION ALL
SELECT 'known case not flagged: FCDO R0 of FY2020-21 as a units error', 'DID030'
WHERE NOT EXISTS (SELECT 1 FROM dw.forecast_return_quality
                  WHERE financial_year = '2020-21' AND return_no = 0 AND rule_code = 'u' AND organisation_code = 'DID030' AND ratio BETWEEN 500 AND 2000)
UNION ALL
SELECT 'known case not flagged: Department of Health missing from R1 of FY2018-19', 'DOH033.GROUP'
WHERE NOT EXISTS (SELECT 1 FROM dw.forecast_return_quality
                  WHERE financial_year = '2018-19' AND return_no = 1 AND rule_code = 'm' AND department_group_code = 'DOH033.GROUP')
UNION ALL
SELECT 'flagged department group not marked in the accuracy table', q.financial_year + ' R' + CAST(q.return_no AS varchar(10)) + ' ' + q.department_group_code
FROM dw.forecast_return_quality AS q
JOIN dw.forecast_accuracy AS a ON a.financial_year = q.financial_year AND a.return_no = q.return_no AND a.department_group_code = q.department_group_code
WHERE a.is_flagged_return = 0
GROUP BY q.financial_year, q.return_no, q.department_group_code
UNION ALL
SELECT 'accuracy row marked flagged without a flag', a.financial_year + ' R' + CAST(a.return_no AS varchar(10)) + ' ' + a.department_group_code
FROM dw.forecast_accuracy AS a
WHERE a.is_flagged_return = 1 AND NOT EXISTS (SELECT 1 FROM dw.forecast_return_quality AS q
      WHERE q.financial_year = a.financial_year AND q.return_no = a.return_no AND q.department_group_code = a.department_group_code)
GROUP BY a.financial_year, a.return_no, a.department_group_code;
