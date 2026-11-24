-- scope: full
-- stg.tac_name_key: the comparison key of a provider name, and the key of every name in the TAC files.
-- The data sheet names a provider by text only; the list of providers gives the NHS (ODS) code. The two
-- spell some names differently: a damaged apostrophe (U+FFFD in "Birmingham Women?s"), "&" against "and",
-- stray commas. The key drops apostrophes and the damaged character, reads "&" as "and", turns commas,
-- full stops, hyphens and slashes into spaces and collapses spaces. Case is ignored by the collation.

DROP TABLE IF EXISTS stg.tac_data_name;
GO
DROP FUNCTION IF EXISTS stg.tac_name_key;
GO

CREATE FUNCTION stg.tac_name_key(@name nvarchar(400))
RETURNS nvarchar(400)
AS
BEGIN
    DECLARE @s nvarchar(400) = @name;
    SET @s = REPLACE(@s, NCHAR(65533), N'');
    SET @s = REPLACE(@s, N'''', N'');
    SET @s = REPLACE(@s, NCHAR(8217), N'');
    SET @s = REPLACE(@s, N'&', N' and ');
    SET @s = REPLACE(REPLACE(REPLACE(REPLACE(@s, N',', N' '), N'.', N' '), N'-', N' '), N'/', N' ');
    SET @s = REPLACE(@s, N'  ', N' ');
    SET @s = REPLACE(@s, N'  ', N' ');
    SET @s = REPLACE(@s, N'  ', N' ');
    SET @s = REPLACE(@s, N'  ', N' ');
    RETURN LTRIM(RTRIM(@s));
END;
GO

-- One row per provider name as it appears in the data sheet of one file.
CREATE TABLE stg.tac_data_name (
    file_id            int           NOT NULL,
    organisation_name  nvarchar(300) NOT NULL,
    name_key           nvarchar(400) NOT NULL,
    CONSTRAINT pk_stg_tac_data_name PRIMARY KEY (file_id, organisation_name)
);
GO

INSERT INTO stg.tac_data_name (file_id, organisation_name, name_key)
SELECT d.file_id, d.organisation_name, stg.tac_name_key(d.organisation_name)
FROM (SELECT DISTINCT file_id, organisation_name FROM raw.tac_value) AS d;
GO
