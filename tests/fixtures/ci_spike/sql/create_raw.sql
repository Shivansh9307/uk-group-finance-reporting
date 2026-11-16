-- CI spike fixture: creates the database, the raw schema and one landing table.
-- Run with sqlcmd -v DB="CiSpike" against master.
IF DB_ID(N'$(DB)') IS NULL
    EXEC (N'CREATE DATABASE [$(DB)]');
GO
USE [$(DB)];
GO
IF SCHEMA_ID(N'raw') IS NULL
    EXEC (N'CREATE SCHEMA raw');
GO
DROP TABLE IF EXISTS raw.spend_line;
CREATE TABLE raw.spend_line
(
    line_id     INT            NOT NULL CONSTRAINT pk_spend_line PRIMARY KEY,
    department  NVARCHAR(100)  NOT NULL,
    description NVARCHAR(400)  NOT NULL,
    amount      DECIMAL(19, 4) NOT NULL
);
GO
