-- Independent of the model: every financial year of the calendar or of a plan, with the outturn of the user's
-- departments where there is one and NULL (a blank) where there is not.
WITH years AS (
    SELECT financial_year FROM dw.dim_period
    UNION
    SELECT financial_year FROM dw.fact_plan
), mine AS (
    SELECT p.financial_year, SUM(f.amount_delta) AS outturn
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    JOIN dw.current_structure_department AS d ON d.department_key = f.current_department_key
    WHERE d.department_number IN (SELECT u.department_number FROM synthetic.user_department AS u WHERE u.user_principal_name = {user})
    GROUP BY p.financial_year
)
SELECT y.financial_year AS [Financial Year], CAST(m.outturn AS decimal(38, 4)) AS outturn
FROM years AS y
LEFT JOIN mine AS m ON m.financial_year = y.financial_year
ORDER BY y.financial_year;
