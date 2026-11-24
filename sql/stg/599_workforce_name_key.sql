-- scope: full
-- stg.workforce_name_key: the one reduction of an organisation name that the workforce rows and the authored map
-- share. Lower case; apostrophes and right single quotes removed; punctuation, dashes and no-break spaces become a
-- space; `&` becomes `and`; runs of spaces collapse. `Education & Skills Funding Agency ` and
-- `Education and Skills Funding Agency` give the same key.

DROP FUNCTION IF EXISTS stg.workforce_name_key;
GO

CREATE FUNCTION stg.workforce_name_key (@name nvarchar(400))
RETURNS TABLE
AS RETURN (
    SELECT CAST(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(
        TRANSLATE(
            REPLACE(REPLACE(REPLACE(REPLACE(LOWER(@name), NCHAR(8217), ''), NCHAR(8211), ' '), NCHAR(160), ' '), '''', ''),
            ',.-()/:;"', '         '),
        '&', ' and '), '  ', ' '), '  ', ' '), '  ', ' '))) AS nvarchar(400)) AS name_key
);
GO
