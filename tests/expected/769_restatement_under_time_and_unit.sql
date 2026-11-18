-- Independent of the model: for each of the two releases, the as-at, first-reported and release-only amounts over three
-- windows of the fact (period 6 of the release's year, periods 0 to 6 of it, period 6 of the year before), then the
-- four time items built from them (current, year to date, previous year, year on year) and the three units. The
-- revision is as at less first reported; its percentage is over the absolute first reported; under year on year the
-- model percentage is missing and the parts-per-million test measure is the difference of the two windows.
WITH cells AS (
    SELECT r.label, r.release_key, y.fiscal_year_start AS ys
    FROM dw.dim_release AS r
    JOIN (SELECT DISTINCT financial_year, fiscal_year_start FROM dw.dim_period) AS y ON y.financial_year = r.financial_year
    WHERE r.label IN ('2021-12', '2024-12')
), scopes AS (
    SELECT s.scope, s.year_offset, s.pmin, s.pmax
    FROM (VALUES ('cur', 0, 6, 6), ('ytd', 0, 0, 6), ('py', -1, 6, 6)) AS s (scope, year_offset, pmin, pmax)
), vals AS (
    SELECT c.label, s.scope,
           SUM(f.amount_delta) AS as_at,
           SUM(CASE WHEN f.revision_no = 0 THEN f.amount_delta END) AS first_amt,
           SUM(CASE WHEN f.release_key = c.release_key THEN f.amount_delta END) AS in_rel
    FROM cells AS c
    CROSS JOIN scopes AS s
    JOIN dw.dim_period AS p ON p.fiscal_year_start = c.ys + s.year_offset AND p.period BETWEEN s.pmin AND s.pmax
    JOIN dw.fact_outturn AS f ON f.period_key = p.period_key AND f.release_key <= c.release_key
    GROUP BY c.label, s.scope
), v2 AS (
    SELECT label, scope, CAST(as_at AS decimal(38, 10)) AS as_at, CAST(first_amt AS decimal(38, 10)) AS first_amt,
           CAST(as_at - first_amt AS decimal(38, 10)) AS rev,
           CAST(as_at - first_amt AS decimal(38, 10)) * 1000000 / NULLIF(ABS(CAST(first_amt AS decimal(38, 10))), 0) AS rev_ppm,
           CAST(as_at - first_amt AS decimal(38, 10)) / NULLIF(ABS(CAST(first_amt AS decimal(38, 10))), 0) AS rev_pct,
           CAST(in_rel AS decimal(38, 10)) AS in_rel
    FROM vals
), items AS (
    SELECT label, N'Current' AS ti, as_at, first_amt, rev, rev_ppm, rev_pct, in_rel FROM v2 WHERE scope = 'cur'
    UNION ALL SELECT label, N'YTD', as_at, first_amt, rev, rev_ppm, rev_pct, in_rel FROM v2 WHERE scope = 'ytd'
    UNION ALL SELECT label, N'PY', as_at, first_amt, rev, rev_ppm, rev_pct, in_rel FROM v2 WHERE scope = 'py'
    UNION ALL SELECT c.label, N'YoY', c.as_at - p.as_at, c.first_amt - p.first_amt, c.rev - p.rev, c.rev_ppm - p.rev_ppm,
                 CAST(NULL AS decimal(38, 10)), c.in_rel - p.in_rel
    FROM v2 AS c JOIN v2 AS p ON p.label = c.label AND p.scope = 'py' WHERE c.scope = 'cur'
), units AS (
    SELECT u.label, u.divisor FROM (VALUES (N'GBP k', CAST(1 AS decimal(19, 4))), (N'GBP m', CAST(1000 AS decimal(19, 4))), (N'GBP bn', CAST(1000000 AS decimal(19, 4)))) AS u (label, divisor)
)
SELECT i.label AS release, u.label AS unit_label, i.ti AS [Time Calculation],
       CAST(i.as_at / u.divisor AS decimal(38, 6)) AS as_at,
       CAST(i.first_amt / u.divisor AS decimal(38, 6)) AS first_reported,
       CAST(i.rev / u.divisor AS decimal(38, 6)) AS revision_since,
       CAST(i.rev_ppm AS decimal(38, 6)) AS revision_percent_ppm,
       CAST(i.rev_pct AS decimal(38, 8)) AS revision_percent,
       CAST(i.in_rel / u.divisor AS decimal(38, 6)) AS in_release
FROM items AS i CROSS JOIN units AS u
ORDER BY i.label, u.label, i.ti;
