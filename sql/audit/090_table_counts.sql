-- audit.table_counts: row count of every user table outside the audit schema, so a build leaves a
-- record of what it produced. Columnstore and heap/clustered tables are counted alike.

DROP TABLE IF EXISTS audit.table_counts;
GO

SELECT
    CAST(s.name AS varchar(128)) AS schema_name,
    CAST(t.name AS varchar(128)) AS table_name,
    CAST(SUM(ps.row_count) AS bigint) AS row_count
INTO audit.table_counts
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.dm_db_partition_stats AS ps ON ps.object_id = t.object_id AND ps.index_id IN (0, 1, 5)
WHERE s.name <> 'audit'
GROUP BY s.name, t.name;
GO

ALTER TABLE audit.table_counts ALTER COLUMN schema_name varchar(128) NOT NULL;
GO
ALTER TABLE audit.table_counts ALTER COLUMN table_name varchar(128) NOT NULL;
GO
ALTER TABLE audit.table_counts ADD CONSTRAINT pk_audit_table_counts PRIMARY KEY (schema_name, table_name);
GO
