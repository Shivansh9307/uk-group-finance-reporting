-- Independent of the model: the sum of the deltas of the release's financial year up to and including the release,
-- by the department number of the department the line belongs to in the current structure.
SELECT r.label AS release, d.department_number AS department_number, CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS as_at
FROM dw.dim_release AS r
JOIN dw.dim_period AS p ON p.financial_year = r.financial_year
JOIN dw.fact_outturn AS f ON f.period_key = p.period_key AND f.release_key <= r.release_key
JOIN dw.dim_department AS d ON d.department_key = f.current_department_key
WHERE r.label IN ('2019-06', '2021-12', '2023-12', '2026-06')
GROUP BY r.label, d.department_number
ORDER BY r.label, d.department_number;
