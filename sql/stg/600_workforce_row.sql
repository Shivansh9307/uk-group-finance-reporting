-- scope: full
-- stg.workforce_row: one row per non-blank row of a workforce file, typed.
--   period_start   the month of the row: from its own Year and Month cells when the file has them, otherwise the month
--                  the file is published for (the older template has neither column). `period_source` says which.
--   period_matches_file   the row's own month equals the month the file is published for. Rows where it does not are
--                  kept here and quarantined in dw (sql/quarantine/605), never moved to another month.
--   name_key       the organisation name reduced to letters and digits, `and` for `&`, for matching to the authored map:
--                  lower case, no punctuation, one space between words. The same reduction is applied to the authored
--                  names in stg.workforce_org_map, so a published spelling and an authored one meet on this key.
-- Only rows of files that are in raw.workforce_file; every row of every file (primary or not) is here.

DROP TABLE IF EXISTS stg.workforce_row;
GO

WITH m AS (
    SELECT * FROM (VALUES ('jan', 1), ('feb', 2), ('mar', 3), ('apr', 4), ('may', 5), ('jun', 6),
                          ('jul', 7), ('aug', 8), ('sep', 9), ('oct', 10), ('nov', 11), ('dec', 12)) AS v (m3, n)
),
r AS (
    SELECT f.file_id, f.dept, f.report_month, f.is_primary, f.format, w.source_row, w.year_text, w.month_text,
           w.organisation_name, w.organisation_type, w.parent_department,
           TRY_CAST(w.year_text AS int) AS row_year,
           COALESCE(mm.n, TRY_CAST(w.month_text AS int)) AS row_month
    FROM raw.workforce_row AS w
    JOIN raw.workforce_file AS f ON f.file_id = w.file_id
    LEFT JOIN m AS mm ON mm.m3 = LOWER(LEFT(LTRIM(w.month_text), 3))
),
k AS (
    SELECT r.*,
           CASE WHEN r.year_text = '' AND r.month_text = '' THEN CAST(CONCAT(r.report_month, '-01') AS date)
                WHEN r.row_year BETWEEN 2000 AND 2100 AND r.row_month BETWEEN 1 AND 12
                    THEN DATEFROMPARTS(r.row_year, r.row_month, 1) END AS period_start,
           CASE WHEN r.year_text = '' AND r.month_text = '' THEN 'file' ELSE 'row' END AS period_source
    FROM r
)
SELECT k.file_id, k.source_row, k.dept, k.report_month, k.is_primary, k.format,
       k.period_start, k.period_source,
       CAST(CASE WHEN k.period_start IS NOT NULL AND FORMAT(k.period_start, 'yyyy-MM') = k.report_month THEN 1 ELSE 0 END AS bit)
           AS period_matches_file,
       k.organisation_name, k.organisation_type, k.parent_department,
       n.name_key
INTO stg.workforce_row
FROM k
CROSS APPLY stg.workforce_name_key(k.organisation_name) AS n;
GO

ALTER TABLE stg.workforce_row ALTER COLUMN file_id int NOT NULL;
ALTER TABLE stg.workforce_row ALTER COLUMN source_row int NOT NULL;
GO

ALTER TABLE stg.workforce_row ADD CONSTRAINT pk_stg_workforce_row PRIMARY KEY (file_id, source_row);
GO
