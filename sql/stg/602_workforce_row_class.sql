-- scope: full
-- stg.workforce_row_class: what happens to each row of a primary copy of a file.
--   status    mapped | excluded | no_map_row | no_organisation_name | empty_row | period_not_file_month
--             empty_row = no organisation name and every published value zero or blank: the spreadsheet template's spare
--             rows, which some departments leave in the file; no_organisation_name = a row with values and no name
--   map_id    the authored map row that decided it (mapped and excluded)
--   durable_key   the organisation the row belongs to (mapped only)
-- A row whose own Year and Month are not the month of its file is never moved to the other month: it is
-- quarantined with status period_not_file_month and counted in the coverage audit.
-- A name that matches two map rows for the month is an error in the map; the test in sql/tests/ catches it.

DROP TABLE IF EXISTS stg.workforce_row_class;
GO

SELECT r.file_id, r.source_row, r.dept, r.report_month, r.period_start, r.organisation_name, r.name_key,
       m.map_id, m.durable_key,
       CAST(CASE WHEN r.name_key = '' AND NOT EXISTS (SELECT 1 FROM raw.workforce_value AS v WHERE v.file_id = r.file_id
                                                       AND v.source_row = r.source_row AND v.value <> 0) THEN 'empty_row'
                 WHEN r.name_key = '' THEN 'no_organisation_name'
                 WHEN r.period_matches_file = 0 THEN 'period_not_file_month'
                 WHEN m.map_id IS NULL THEN 'no_map_row'
                 WHEN m.decision = 'map' THEN 'mapped'
                 ELSE 'excluded' END AS varchar(30)) AS status
INTO stg.workforce_row_class
FROM stg.workforce_row AS r
LEFT JOIN stg.workforce_org_map AS m
       ON m.dept = r.dept AND m.name_key = r.name_key
      AND (m.valid_from IS NULL OR m.valid_from <= r.period_start)
      AND (m.valid_to IS NULL OR m.valid_to >= r.period_start)
WHERE r.is_primary = 1;
GO

ALTER TABLE stg.workforce_row_class ALTER COLUMN file_id int NOT NULL;
ALTER TABLE stg.workforce_row_class ALTER COLUMN source_row int NOT NULL;
GO

ALTER TABLE stg.workforce_row_class ADD CONSTRAINT pk_stg_workforce_row_class PRIMARY KEY (file_id, source_row);
GO
