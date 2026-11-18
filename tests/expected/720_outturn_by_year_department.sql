-- Independent of the model: the fact summed on the financial year of its period and the department number of the
-- current structure, from the warehouse tables.
SELECT p.financial_year AS [Financial Year], d.department_number AS [Department Number],
       CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS outturn
FROM dw.fact_outturn AS f
JOIN dw.dim_period AS p ON p.period_key = f.period_key
JOIN dw.current_structure_department AS d ON d.department_key = f.current_department_key
GROUP BY p.financial_year, d.department_number
ORDER BY p.financial_year, d.department_number;
