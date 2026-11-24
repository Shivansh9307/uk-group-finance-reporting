-- scope: full
-- dw.workforce_month: workforce and paybill by durable organisation, month and measure. REAL data (the published files);
-- the only authored input is the map that says which organisation a published name is (authored.workforce_org_map).
-- Grain: (durable_key, month_start, measure_key). Several published rows can be one organisation in a month (an
-- executive agency counted in its department, a name published twice): the value is their sum, `source_rows` says how
-- many rows, `rolled_up_rows` how many of those the map marks as an agency counted in its parent department or a body that is part of the organisation.
--   value            DECIMAL(19,4): headcount and full-time equivalent are people; paybill and costs are pounds (unit in
--                    dw.dim_workforce_measure). The published number is rounded to 4 decimal places on the way in.
--   source_priority  the largest priority of any row in the cell: 1 = the file's own total, 2 or 3 = rebuilt from
--                    components because the total was blank (dw.workforce_measure_rule)
--   publisher        the series of the file the numbers come from (one organisation has one publisher in a month: tested)
-- Only rows of the primary copy of each file, and only rows the map decides (quarantine.workforce_row has the rest).

DROP TABLE IF EXISTS dw.workforce_month;
GO

WITH x AS (
    SELECT c.file_id, c.source_row, c.durable_key, c.period_start, c.dept, c.map_id,
           r.measure_key, r.priority, v.value
    FROM stg.workforce_row_class AS c
    JOIN raw.workforce_value AS v ON v.file_id = c.file_id AND v.source_row = c.source_row
    JOIN dw.workforce_measure_rule AS r ON r.raw_key = v.measure_key
    WHERE c.status = 'mapped'
),
best AS (
    SELECT file_id, source_row, measure_key, MIN(priority) AS priority
    FROM x GROUP BY file_id, source_row, measure_key
),
line AS (
    SELECT x.file_id, x.source_row, x.durable_key, x.period_start, x.dept, x.map_id, x.measure_key, b.priority,
           SUM(x.value) AS value
    FROM x JOIN best AS b ON b.file_id = x.file_id AND b.source_row = x.source_row
                         AND b.measure_key = x.measure_key AND b.priority = x.priority
    GROUP BY x.file_id, x.source_row, x.durable_key, x.period_start, x.dept, x.map_id, x.measure_key, b.priority
)
SELECT l.durable_key,
       CAST(FORMAT(l.period_start, 'yyyy-MM') AS char(7)) AS report_month,
       l.period_start AS month_start,
       l.measure_key,
       CAST(SUM(l.value) AS decimal(19, 4)) AS value,
       CAST(COUNT(*) AS int) AS source_rows,
       CAST(SUM(CASE WHEN m.basis IN ('agency_into_parent', 'part_of') THEN 1 ELSE 0 END) AS int) AS rolled_up_rows,
       CAST(MAX(l.priority) AS tinyint) AS source_priority,
       CAST(MIN(l.dept) AS varchar(20)) AS publisher
INTO dw.workforce_month
FROM line AS l
JOIN stg.workforce_org_map AS m ON m.map_id = l.map_id
GROUP BY l.durable_key, l.period_start, l.measure_key;
GO

ALTER TABLE dw.workforce_month ALTER COLUMN durable_key varchar(20) NOT NULL;
ALTER TABLE dw.workforce_month ALTER COLUMN report_month char(7) NOT NULL;
ALTER TABLE dw.workforce_month ALTER COLUMN month_start date NOT NULL;
ALTER TABLE dw.workforce_month ALTER COLUMN measure_key varchar(40) NOT NULL;
GO

ALTER TABLE dw.workforce_month ADD CONSTRAINT pk_dw_workforce_month PRIMARY KEY (durable_key, month_start, measure_key);
ALTER TABLE dw.workforce_month ADD CONSTRAINT fk_dw_workforce_month_measure
    FOREIGN KEY (measure_key) REFERENCES dw.dim_workforce_measure (measure_key);
GO
