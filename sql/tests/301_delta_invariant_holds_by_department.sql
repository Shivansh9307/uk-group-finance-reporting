-- test: for every release R, the deltas up to R for R's financial year equal R's snapshot for every department as reported
WITH snap AS (
    SELECT r.release_seq, m.department_key, SUM(s.amount) AS amount
    FROM stg.inyear_snapshot AS s
    JOIN stg.release AS r ON r.release = s.release
    JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
    GROUP BY r.release_seq, m.department_key
), asat AS (
    SELECT r.release_seq, f.department_key, SUM(f.amount_delta) AS amount
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    JOIN dw.dim_release AS r ON r.financial_year = p.financial_year AND r.release_key >= f.release_key
    GROUP BY r.release_seq, f.department_key
)
SELECT COALESCE(a.release_seq, s.release_seq) AS release_seq, COALESCE(a.department_key, s.department_key) AS department_key,
       a.amount AS as_at_from_deltas, s.amount AS reported
FROM asat AS a
FULL OUTER JOIN snap AS s ON s.release_seq = a.release_seq AND s.department_key = a.department_key
WHERE ISNULL(a.amount, 0) <> ISNULL(s.amount, 0);
