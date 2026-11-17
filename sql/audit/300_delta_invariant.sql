-- audit.delta_invariant: for every release, what the release reports against what the deltas add up to.
--   snapshot_total      SUM(amount) of the release's rows in stg.inyear_snapshot (GBP thousands)
--   as_at_total         SUM(amount_delta) in dw.fact_outturn over releases up to this one, for this release's
--                       financial year only
--   difference          as_at_total - snapshot_total; zero for every release
--   control_total       amount_sum_rounded_4dp from data/audit/inyear_file_control_totals.csv (the control
--                       table the loader is checked against), for the release's primary file
--   difference_to_control   as_at_total - control_total; zero for every release
--   fact_rows           delta rows of this release in dw.fact_outturn
-- The line-by-line version of the same invariant, and the one by department, are in sql/tests/300-310.

DROP TABLE IF EXISTS audit.delta_invariant;
GO

SELECT
    r.release_key,
    CAST(r.label AS varchar(7)) AS release,
    CAST(r.financial_year AS varchar(7)) AS financial_year,
    CAST(s.snapshot_rows AS int) AS snapshot_rows,
    CAST(s.snapshot_total AS decimal(38,4)) AS snapshot_total,
    CAST(a.as_at_total AS decimal(38,4)) AS as_at_total,
    CAST(a.as_at_total - s.snapshot_total AS decimal(38,4)) AS difference,
    CAST(e.amount_sum_rounded_4dp AS decimal(38,4)) AS control_total,
    CAST(a.as_at_total - CAST(e.amount_sum_rounded_4dp AS decimal(38,4)) AS decimal(38,4)) AS difference_to_control,
    CAST(f.fact_rows AS int) AS fact_rows,
    CAST(CASE WHEN a.as_at_total = s.snapshot_total AND a.as_at_total = CAST(e.amount_sum_rounded_4dp AS decimal(38,4))
              THEN 'pass' ELSE 'fail' END AS varchar(4)) AS status
INTO audit.delta_invariant
FROM dw.dim_release AS r
JOIN raw.oscar_inyear_file AS pf ON pf.release = r.label AND pf.primary_for_release = 'Y'
JOIN raw.oscar_inyear_control_expected AS e ON e.release = pf.release AND e.filename = pf.filename
CROSS APPLY (
    SELECT COUNT_BIG(*) AS snapshot_rows, ISNULL(SUM(x.amount), 0) AS snapshot_total
    FROM stg.inyear_snapshot AS x WHERE x.release = r.label
) AS s
CROSS APPLY (
    SELECT ISNULL(SUM(f.amount_delta), 0) AS as_at_total
    FROM dw.fact_outturn AS f
    JOIN dw.dim_period AS p ON p.period_key = f.period_key
    WHERE f.release_key <= r.release_key AND p.financial_year = r.financial_year
) AS a
CROSS APPLY (
    SELECT COUNT_BIG(*) AS fact_rows FROM dw.fact_outturn AS f WHERE f.release_key = r.release_key
) AS f;
GO

ALTER TABLE audit.delta_invariant ALTER COLUMN release_key int NOT NULL;
GO
ALTER TABLE audit.delta_invariant ADD CONSTRAINT pk_audit_delta_invariant PRIMARY KEY (release_key);
GO
