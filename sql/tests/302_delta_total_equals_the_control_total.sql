-- test: for every release the deltas up to it for its financial year add up to amount_sum_rounded_4dp of the release's primary file in the control table
SELECT r.release_key, r.label, a.as_at_total, e.amount_sum_rounded_4dp
FROM dw.dim_release AS r
JOIN raw.oscar_inyear_file AS pf ON pf.release = r.label AND pf.primary_for_release = 'Y'
JOIN raw.oscar_inyear_control_expected AS e ON e.release = pf.release AND e.filename = pf.filename
CROSS APPLY (
    SELECT ISNULL(SUM(f.amount_delta), 0) AS as_at_total
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    WHERE f.release_key <= r.release_key AND p.financial_year = r.financial_year
) AS a
WHERE a.as_at_total <> CAST(e.amount_sum_rounded_4dp AS decimal(38,4))
UNION ALL
SELECT release_key, release, as_at_total, control_total FROM audit.delta_invariant WHERE status <> 'pass'
UNION ALL
SELECT 0, 'release count', (SELECT COUNT(*) FROM dw.dim_release), 31
FROM (VALUES (1)) AS one (x)
WHERE (SELECT COUNT(*) FROM dw.dim_release) <> 31;
