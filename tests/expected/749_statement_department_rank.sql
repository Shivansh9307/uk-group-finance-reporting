-- Independent of the model: RANK() OVER the departments of the current structure by statement amount, largest first, for
-- each line in 2023-24, over the departments that have an amount.
WITH ln AS (
    SELECT line_key, line_id, sign_factor FROM dw.statement_line WHERE line_id IN ('R30', 'R50', 'TOT')
), amt AS (
    SELECT l.line_id, d.department_number, SUM(f.amount_delta) * MAX(l.sign_factor) AS amount
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    JOIN dw.dim_department AS d ON d.department_key = f.current_department_key
    JOIN dw.account_statement_line AS a ON a.account_key = f.account_key
    JOIN dw.statement_line_member AS m ON m.detail_line_key = a.line_key
    JOIN ln AS l ON l.line_key = m.line_key
    WHERE p.financial_year = '2023-24'
    GROUP BY l.line_id, d.department_number
)
SELECT line_id AS [Line Id], department_number AS [Department Number], CAST(amount AS decimal(38, 4)) AS statement_amount,
       RANK() OVER (PARTITION BY line_id ORDER BY amount DESC) AS department_rank
FROM amt
ORDER BY line_id, department_number;
