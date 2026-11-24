-- scope: full
-- quarantine.workforce_row: every row of a primary workforce file that is not in dw.workforce_month, with the reason.
--   reason_code   empty_row (a spare template row: no name, every value zero or blank) | excluded (I reviewed the name and it has no organisation of its own in OSCAR; the reason is the map's)
--                 | no_map_row (a published name nobody has decided; a test requires there to be none)
--                 | no_organisation_name | period_not_file_month
--   payroll_fte, payroll_paybill_gbp   the row's published payroll full-time equivalent and paybill (NULL when blank)
-- Nothing is dropped: dw.workforce_month plus this table account for every row of every primary file.

DROP TABLE IF EXISTS quarantine.workforce_row;
GO

SELECT c.file_id, c.source_row, c.dept, c.report_month, c.organisation_name, c.status AS reason_code,
       CAST(CASE c.status
                WHEN 'excluded' THEN m.reason
                WHEN 'no_map_row' THEN N'no row in authored.workforce_org_map for this name'
                WHEN 'no_organisation_name' THEN N'the row has values but no organisation name'
                WHEN 'empty_row' THEN N'a spare template row: no organisation name and every value zero or blank'
                ELSE N'the row''s own Year and Month are not the month of its file' END AS nvarchar(400)) AS reason_detail,
       c.map_id,
       f.payroll_fte, f.payroll_paybill_gbp
INTO quarantine.workforce_row
FROM stg.workforce_row_class AS c
LEFT JOIN stg.workforce_org_map AS m ON m.map_id = c.map_id
OUTER APPLY (
    SELECT MAX(CASE WHEN v.measure_key = 'payroll_total_fte' THEN v.value END) AS payroll_fte,
           MAX(CASE WHEN v.measure_key = 'cost_payroll_paybill_gbp' THEN v.value END) AS payroll_paybill_gbp
    FROM raw.workforce_value AS v WHERE v.file_id = c.file_id AND v.source_row = c.source_row
) AS f
WHERE c.status <> 'mapped';
GO

ALTER TABLE quarantine.workforce_row ALTER COLUMN file_id int NOT NULL;
ALTER TABLE quarantine.workforce_row ALTER COLUMN source_row int NOT NULL;
GO

ALTER TABLE quarantine.workforce_row ADD CONSTRAINT pk_quarantine_workforce_row PRIMARY KEY (file_id, source_row);
GO
