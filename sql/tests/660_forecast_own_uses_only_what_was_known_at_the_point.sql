-- test: no leakage. Every own-forecast row at point n carries lineage that says its inputs come from return n and from months up to n; the input table equals, both ways, the rows of dw.forecast_return with return = n and month <= n; the prior-year profile equals the R13 of the prior year; and both methods recomputed from that restricted set alone (same arithmetic and the seasonal guard, read straight from dw.forecast_return) equal dw.forecast_own exactly
-- requires: dw.forecast_own, dw.forecast_own_input, dw.forecast_prior_profile, dw.forecast_return, dw.forecast_return_header
WITH months AS (
    SELECT m.period FROM (VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12)) AS m (period)
),
known AS (
    SELECT r.financial_year, r.return_no, r.department_group_code, r.budget_measure, r.period, SUM(r.amount) AS amount
    FROM dw.forecast_return AS r
    WHERE r.return_no BETWEEN 1 AND 12 AND r.period BETWEEN 1 AND r.return_no AND r.budget_measure IN ('RDEL', 'CDEL', 'AME')
    GROUP BY r.financial_year, r.return_no, r.department_group_code, r.budget_measure, r.period
),
ytd AS (
    SELECT financial_year, return_no, department_group_code, budget_measure, SUM(amount) AS ytd_amount
    FROM known GROUP BY financial_year, return_no, department_group_code, budget_measure
),
prior AS (
    SELECT c.financial_year, p.financial_year AS profile_year, r.department_group_code, r.budget_measure, r.period, SUM(r.amount) AS amount
    FROM dw.forecast_return_header AS p
    JOIN dw.forecast_return_header AS c ON c.year_seq = p.year_seq + 1 AND c.return_no = 13
    JOIN dw.forecast_return AS r ON r.financial_year = p.financial_year AND r.return_no = 13
    WHERE p.return_no = 13 AND r.period BETWEEN 1 AND 12 AND r.budget_measure IN ('RDEL', 'CDEL', 'AME')
    GROUP BY c.financial_year, p.financial_year, r.department_group_code, r.budget_measure, r.period
),
prior_ytd AS (
    SELECT y.financial_year, y.return_no, y.department_group_code, y.budget_measure,
           SUM(CASE WHEN p.period <= y.return_no THEN p.amount ELSE 0 END) AS profile_ytd, SUM(p.amount) AS profile_year
    FROM ytd AS y
    JOIN prior AS p ON p.financial_year = y.financial_year AND p.department_group_code = y.department_group_code
                   AND p.budget_measure = y.budget_measure
    GROUP BY y.financial_year, y.return_no, y.department_group_code, y.budget_measure
),
expected AS (
    SELECT y.financial_year, y.return_no, y.department_group_code, y.budget_measure, 'run_rate' AS method, mo.period,
           CAST(CAST(y.ytd_amount AS decimal(20, 6)) / CAST(y.return_no AS decimal(10, 0)) AS decimal(19, 4)) AS amount
    FROM ytd AS y JOIN months AS mo ON mo.period > y.return_no
    UNION ALL
    SELECT y.financial_year, y.return_no, y.department_group_code, y.budget_measure, 'seasonal', mo.period,
           CAST(CAST(y.ytd_amount AS decimal(20, 6)) * CAST(COALESCE(p.amount, 0) AS decimal(20, 6)) / CAST(py.profile_ytd AS decimal(20, 6)) AS decimal(19, 4))
    FROM ytd AS y
    JOIN months AS mo ON mo.period > y.return_no
    JOIN prior_ytd AS py ON py.financial_year = y.financial_year AND py.return_no = y.return_no
                        AND py.department_group_code = y.department_group_code AND py.budget_measure = y.budget_measure
                        AND (py.profile_ytd > 0 AND y.ytd_amount > 0 OR py.profile_ytd < 0 AND y.ytd_amount < 0)
                        AND ABS(py.profile_ytd) * 10 >= ABS(py.profile_year)
    LEFT JOIN prior AS p ON p.financial_year = y.financial_year AND p.department_group_code = y.department_group_code
                        AND p.budget_measure = y.budget_measure AND p.period = mo.period
)
SELECT 'own forecast row has lineage outside its point' AS problem, o.financial_year + ' R' + CAST(o.return_no AS varchar(10)) AS detail, CAST(COUNT(*) AS varchar(20)) AS found
FROM dw.forecast_own AS o
WHERE o.input_return_no <> o.return_no OR o.input_max_period > o.return_no OR o.period <= o.return_no
GROUP BY o.financial_year, o.return_no
UNION ALL
SELECT 'input table differs from the known set (return n, months up to n)', 'in table only', CAST(COUNT(*) AS varchar(20))
FROM (SELECT financial_year, return_no, department_group_code, budget_measure, period, amount, source_rows FROM dw.forecast_own_input
      EXCEPT
      SELECT r.financial_year, r.return_no, r.department_group_code, r.budget_measure, r.period, SUM(r.amount), SUM(r.source_rows)
      FROM dw.forecast_return AS r
      WHERE r.return_no BETWEEN 1 AND 12 AND r.period BETWEEN 1 AND r.return_no AND r.budget_measure IN ('RDEL', 'CDEL', 'AME')
      GROUP BY r.financial_year, r.return_no, r.department_group_code, r.budget_measure, r.period) AS x
HAVING COUNT(*) > 0
UNION ALL
SELECT 'input table differs from the known set (return n, months up to n)', 'in the known set only', CAST(COUNT(*) AS varchar(20))
FROM (SELECT r.financial_year, r.return_no, r.department_group_code, r.budget_measure, r.period, SUM(r.amount) AS amount, SUM(r.source_rows) AS source_rows
      FROM dw.forecast_return AS r
      WHERE r.return_no BETWEEN 1 AND 12 AND r.period BETWEEN 1 AND r.return_no AND r.budget_measure IN ('RDEL', 'CDEL', 'AME')
      GROUP BY r.financial_year, r.return_no, r.department_group_code, r.budget_measure, r.period
      EXCEPT
      SELECT financial_year, return_no, department_group_code, budget_measure, period, amount, source_rows FROM dw.forecast_own_input) AS x
HAVING COUNT(*) > 0
UNION ALL
SELECT 'prior-year profile differs from R13 of the prior year', 'rows that differ', CAST(COUNT(*) AS varchar(20))
FROM (SELECT p.financial_year, p.profile_year, p.department_group_code, p.budget_measure, p.period, p.amount FROM prior AS p
      EXCEPT
      SELECT financial_year, profile_financial_year, department_group_code, budget_measure, period, amount FROM dw.forecast_prior_profile) AS x
HAVING COUNT(*) > 0
UNION ALL
SELECT 'prior-year profile has a row the prior-year R13 does not', 'rows that differ', CAST(COUNT(*) AS varchar(20))
FROM (SELECT financial_year, profile_financial_year, department_group_code, budget_measure, period, amount FROM dw.forecast_prior_profile
      EXCEPT
      SELECT p.financial_year, p.profile_year, p.department_group_code, p.budget_measure, p.period, p.amount FROM prior AS p) AS x
HAVING COUNT(*) > 0
UNION ALL
SELECT 'recomputation from the restricted set differs from dw.forecast_own', COALESCE(e.financial_year, o.financial_year) + ' R' + CAST(COALESCE(e.return_no, o.return_no) AS varchar(10)) + ' ' + COALESCE(e.method, o.method),
       CAST(e.amount AS varchar(40)) + ' vs ' + CAST(o.amount AS varchar(40))
FROM expected AS e
FULL OUTER JOIN dw.forecast_own AS o
  ON o.financial_year = e.financial_year AND o.return_no = e.return_no AND o.department_group_code = e.department_group_code
 AND o.budget_measure = e.budget_measure AND o.method = e.method AND o.period = e.period
WHERE e.amount IS NULL OR o.amount IS NULL OR e.amount <> o.amount;
