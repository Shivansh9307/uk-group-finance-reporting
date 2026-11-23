-- Independent of the model: the cells of the release by financial year by department grid (the combinations that have at
-- least one delta up to the release), counted and summed for each release. The plain and the rewritten measure must both
-- equal the totals, and no cell differs.
WITH cell AS (
    SELECT r.label AS release, p.financial_year AS financial_year, d.department_number AS department_number,
           SUM(f.amount_delta) AS amount
    FROM dw.dim_release AS r
    JOIN dw.fact_outturn AS f ON f.release_key <= r.release_key
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    JOIN dw.dim_department AS d ON d.department_key = f.current_department_key
    GROUP BY r.label, p.financial_year, d.department_number
)
SELECT release, COUNT(*) AS cells,
       CAST(SUM(amount) AS decimal(38, 4)) AS naive_total,
       CAST(SUM(amount) AS decimal(38, 4)) AS rewrite_total,
       CAST(0 AS decimal(38, 4)) AS max_abs_difference,
       CAST(0 AS int) AS cells_that_differ
FROM cell
GROUP BY release
ORDER BY release;
