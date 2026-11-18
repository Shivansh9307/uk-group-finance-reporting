-- test: for every release the fact's as-at total by current department equals its total by reported department and the snapshot total, and by current department it equals the snapshot recomputed through the map
WITH asat AS (
    SELECT r.release_seq, f.current_department_key, f.department_key, f.amount_delta
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    JOIN dw.dim_release AS r ON r.financial_year = p.financial_year AND r.release_key >= f.release_key
), tot_cur AS (
    SELECT release_seq, SUM(amount_delta) AS amount FROM asat GROUP BY release_seq
), by_cur AS (
    SELECT release_seq, current_department_key, SUM(amount_delta) AS amount FROM asat GROUP BY release_seq, current_department_key
), by_rep AS (
    SELECT release_seq, department_key, SUM(amount_delta) AS amount FROM asat GROUP BY release_seq, department_key
), snap AS (
    SELECT r.release_seq, m.department_key, c.current_department_key, SUM(s.amount) AS amount
    FROM stg.inyear_snapshot AS s
    JOIN stg.release AS r ON r.release = s.release
    JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
    JOIN stg.current_structure_map AS c ON c.organisation_key = m.organisation_key AND c.sub_segment_code = s.sub_segment_code
    GROUP BY r.release_seq, m.department_key, c.current_department_key
), snap_tot AS (
    SELECT release_seq, SUM(amount) AS amount FROM snap GROUP BY release_seq
), snap_cur AS (
    SELECT release_seq, current_department_key, SUM(amount) AS amount FROM snap GROUP BY release_seq, current_department_key
), snap_rep AS (
    SELECT release_seq, department_key, SUM(amount) AS amount FROM snap GROUP BY release_seq, department_key
)
SELECT t.release_seq, 'total by current department differs from the snapshot' AS problem, t.amount AS fact_amount, s.amount AS snapshot_amount
FROM tot_cur AS t FULL OUTER JOIN snap_tot AS s ON s.release_seq = t.release_seq
WHERE ISNULL(t.amount, 0) <> ISNULL(s.amount, 0)
UNION ALL
SELECT COALESCE(a.release_seq, b.release_seq), 'current department differs from the snapshot through the map', a.amount, b.amount
FROM by_cur AS a FULL OUTER JOIN snap_cur AS b ON b.release_seq = a.release_seq AND b.current_department_key = a.current_department_key
WHERE ISNULL(a.amount, 0) <> ISNULL(b.amount, 0)
UNION ALL
SELECT COALESCE(a.release_seq, b.release_seq), 'reported department differs from the snapshot', a.amount, b.amount
FROM by_rep AS a FULL OUTER JOIN snap_rep AS b ON b.release_seq = a.release_seq AND b.department_key = a.department_key
WHERE ISNULL(a.amount, 0) <> ISNULL(b.amount, 0);
