-- test: the total line of the statement equals the sum of dw.fact_outturn in every financial year, and the sum of the detail lines equals it too, so no amount is lost or counted twice
WITH f AS (
    SELECT p.financial_year, SUM(o.amount_delta) AS amt
    FROM dw.fact_outturn AS o JOIN dw.dim_period AS p ON p.period_key = o.period_key
    GROUP BY p.financial_year
), tot AS (
    SELECT s.financial_year, s.outturn_as_reported AS amt FROM dw.v_statement_pnl AS s WHERE s.line_id = 'TOT'
), det AS (
    SELECT s.financial_year, SUM(s.outturn_as_reported) AS amt
    FROM dw.v_statement_pnl AS s JOIN dw.statement_line AS l ON l.line_id = s.line_id
    WHERE l.line_type = 'detail'
    GROUP BY s.financial_year
)
SELECT 'total line differs from the fact' AS problem, f.financial_year AS detail, f.amt AS fact_amt, tot.amt AS statement_amt
FROM f LEFT JOIN tot ON tot.financial_year = f.financial_year
WHERE tot.amt IS NULL OR ABS(tot.amt - f.amt) > 0.0001
UNION ALL
SELECT 'detail lines differ from the fact', f.financial_year, f.amt, det.amt
FROM f LEFT JOIN det ON det.financial_year = f.financial_year
WHERE det.amt IS NULL OR ABS(det.amt - f.amt) > 0.0001
UNION ALL
SELECT 'statement total of all years differs from the fact', 'all', (SELECT SUM(amount_delta) FROM dw.fact_outturn),
       (SELECT SUM(amt) FROM tot)
WHERE ABS((SELECT SUM(amount_delta) FROM dw.fact_outturn) - (SELECT SUM(amt) FROM tot)) > 0.0001;
