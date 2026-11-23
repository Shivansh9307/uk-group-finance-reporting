-- Independent of the model: the sum of the deltas up to and including each release, by the department number of the
-- department the line belongs to in the current structure. The plain and the rewritten measure must both equal it, so the
-- difference is 0.
SELECT r.label AS release, d.department_number AS department_number,
       CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS as_at_naive,
       CAST(SUM(f.amount_delta) AS decimal(38, 4)) AS as_at_rewrite,
       CAST(0 AS decimal(38, 4)) AS difference
FROM dw.dim_release AS r
JOIN dw.fact_outturn AS f ON f.release_key <= r.release_key
JOIN dw.dim_department AS d ON d.department_key = f.current_department_key
GROUP BY r.label, d.department_number
ORDER BY r.label, d.department_number;
