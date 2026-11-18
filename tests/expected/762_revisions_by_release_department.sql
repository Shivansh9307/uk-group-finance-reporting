-- Independent of the model: per department (current structure) and release, the delta rows are summed (all, first
-- reported = revision 0, restating = revision above 0, and their absolute values), then added up over the releases of
-- the financial year with window functions over a grid of every release. As at and first reported run from the first
-- release of the year to the release; the change and the gross forms are the release's own rows.
WITH dept AS (
    SELECT DISTINCT d.department_number
    FROM dw.fact_outturn AS f JOIN dw.dim_department AS d ON d.department_key = f.current_department_key
), grid AS (
    SELECT dp.department_number, r.release_key, r.label, r.financial_year
    FROM dept AS dp CROSS JOIN dw.dim_release AS r
), d AS (
    SELECT dd.department_number, f.release_key,
           COUNT_BIG(*) AS n,
           SUM(f.amount_delta) AS delta,
           SUM(CASE WHEN f.revision_no = 0 THEN f.amount_delta ELSE 0 END) AS first_delta,
           SUM(CASE WHEN f.revision_no = 0 THEN 1 ELSE 0 END) AS first_n,
           SUM(CASE WHEN f.revision_no > 0 THEN f.amount_delta ELSE 0 END) AS restate_delta,
           SUM(CASE WHEN f.revision_no > 0 THEN 1 ELSE 0 END) AS restate_n,
           SUM(ABS(f.amount_delta)) AS gross,
           SUM(CASE WHEN f.revision_no > 0 THEN ABS(f.amount_delta) ELSE 0 END) AS gross_restate
    FROM dw.fact_outturn AS f
    JOIN dw.dim_department AS dd ON dd.department_key = f.current_department_key
    GROUP BY dd.department_number, f.release_key
), w AS (
    SELECT g.department_number, g.label, g.financial_year, g.release_key,
           d.n, d.delta, d.restate_n, d.restate_delta, d.gross, d.gross_restate,
           SUM(ISNULL(d.n, 0)) OVER (PARTITION BY g.department_number, g.financial_year ORDER BY g.release_key ROWS UNBOUNDED PRECEDING) AS cum_n,
           SUM(ISNULL(d.delta, 0)) OVER (PARTITION BY g.department_number, g.financial_year ORDER BY g.release_key ROWS UNBOUNDED PRECEDING) AS as_at,
           SUM(ISNULL(d.first_n, 0)) OVER (PARTITION BY g.department_number, g.financial_year ORDER BY g.release_key ROWS UNBOUNDED PRECEDING) AS cum_first_n,
           SUM(ISNULL(d.first_delta, 0)) OVER (PARTITION BY g.department_number, g.financial_year ORDER BY g.release_key ROWS UNBOUNDED PRECEDING) AS first_reported
    FROM grid AS g
    LEFT JOIN d ON d.department_number = g.department_number AND d.release_key = g.release_key
)
SELECT w.label AS release, w.department_number AS department_number,
       CAST(w.as_at AS decimal(38, 4)) AS as_at,
       CAST(CASE WHEN w.cum_first_n > 0 THEN w.first_reported END AS decimal(38, 4)) AS first_reported,
       CAST(CASE WHEN w.cum_first_n > 0 THEN w.as_at - w.first_reported END AS decimal(38, 4)) AS revision_since,
       CAST(CASE WHEN w.cum_first_n > 0 AND w.first_reported <> 0
                 THEN CAST(w.as_at - w.first_reported AS decimal(38, 10)) * 1000000 / ABS(CAST(w.first_reported AS decimal(38, 10))) END AS decimal(38, 6)) AS revision_percent,
       CAST(w.delta AS decimal(38, 4)) AS in_release,
       CAST(CASE WHEN w.restate_n > 0 THEN w.restate_delta END AS decimal(38, 4)) AS restatement,
       CAST(w.gross AS decimal(38, 4)) AS gross,
       CAST(CASE WHEN w.restate_n > 0 THEN w.gross_restate END AS decimal(38, 4)) AS gross_restatement
FROM w
WHERE w.label IN ('2019-06', '2020-12', '2021-12', '2023-12', '2025-12', '2026-06') AND w.cum_n > 0
ORDER BY w.label, w.department_number;
