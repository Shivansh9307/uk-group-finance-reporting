-- scope: full
-- audit.tac_year_summary: one row per year and provider type, what the load delivered and how it was controlled.
--   providers_listed / providers_with_data / providers_in_fact   the list of providers, the data sheet, the fact
--   fact_rows                                                    rows of dw.tac_fact (both columns)
--   control_difference   the sum of the absolute differences of audit.tac_file_control_totals over the three
--                        statements: raw against the independent sum, stg against rounded raw, fact against stg
--   rows_quarantined     rows rejected at load plus rows that could not enter the fact
-- All three differences are exactly 0 when the load is right.

DROP TABLE IF EXISTS audit.tac_year_summary;
GO

SELECT f.release, f.provider_type, f.filename,
       (SELECT COUNT(*) FROM dw.tac_provider_year AS y WHERE y.release = f.release AND y.provider_type = f.provider_type)
           AS providers_listed,
       (SELECT COUNT(*) FROM dw.tac_provider_year AS y
        WHERE y.release = f.release AND y.provider_type = f.provider_type AND y.has_statement_data = 1) AS providers_with_data,
       (SELECT COUNT(DISTINCT t.provider_key) FROM dw.tac_fact AS t
        JOIN dw.tac_provider_year AS y ON y.provider_key = t.provider_key AND y.release = t.release
        WHERE t.release = f.release AND y.provider_type = f.provider_type) AS providers_in_fact,
       (SELECT COUNT_BIG(*) FROM dw.tac_fact AS t
        JOIN dw.tac_provider_year AS y ON y.provider_key = t.provider_key AND y.release = t.release
        WHERE t.release = f.release AND y.provider_type = f.provider_type) AS fact_rows,
       c.control_difference, c.rows_quarantined
INTO audit.tac_year_summary
FROM raw.tac_file AS f
CROSS APPLY (SELECT SUM(ABS(ISNULL(k.difference, 0)) + ABS(ISNULL(k.difference_stg, 0)) + ABS(ISNULL(k.difference_fact, 0)))
                        AS control_difference,
                    SUM(k.rows_rejected + k.rows_unmapped) AS rows_quarantined
             FROM audit.tac_file_control_totals AS k
             WHERE k.filename = f.filename AND k.loaded = 1) AS c
WHERE f.file_kind = 'data';
GO

ALTER TABLE audit.tac_year_summary ALTER COLUMN release varchar(7) NOT NULL;
GO
ALTER TABLE audit.tac_year_summary ALTER COLUMN provider_type varchar(30) NOT NULL;
GO
ALTER TABLE audit.tac_year_summary ADD CONSTRAINT pk_audit_tac_year_summary PRIMARY KEY (release, provider_type);
GO
