-- audit.table_counts: row count of every user table outside the audit schema, so a build leaves a
-- record of what it produced. Columnstore and heap/clustered tables are counted alike.
-- A bulk load into a columnstore table can leave a TOMBSTONE row group (a delta row group already moved into
-- a compressed one, waiting for the background cleanup). dm_db_partition_stats still counts its rows, so
-- they are taken off: otherwise the count depends on when the cleanup ran.

DROP TABLE IF EXISTS audit.table_counts;
GO

SELECT
    CAST(s.name AS varchar(128)) AS schema_name,
    CAST(t.name AS varchar(128)) AS table_name,
    CAST(SUM(ps.row_count) - ISNULL(MAX(tb.tombstone_rows), 0) AS bigint) AS row_count
INTO audit.table_counts
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.dm_db_partition_stats AS ps ON ps.object_id = t.object_id AND ps.index_id IN (0, 1, 5)
LEFT JOIN (SELECT object_id, SUM(CAST(total_rows AS bigint)) AS tombstone_rows
           FROM sys.dm_db_column_store_row_group_physical_stats
           WHERE state_desc = 'TOMBSTONE'
           GROUP BY object_id) AS tb ON tb.object_id = t.object_id
WHERE s.name <> 'audit'
GROUP BY s.name, t.name;
GO

ALTER TABLE audit.table_counts ALTER COLUMN schema_name varchar(128) NOT NULL;
GO
ALTER TABLE audit.table_counts ALTER COLUMN table_name varchar(128) NOT NULL;
GO
ALTER TABLE audit.table_counts ADD CONSTRAINT pk_audit_table_counts PRIMARY KEY (schema_name, table_name);
GO
