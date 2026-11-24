-- scope: full
-- stg.tac_provider_year: one row per provider listed in a data file's `List of providers` sheet.
--   provider_code        the NHS (ODS) code, which is the key of a provider: names change, codes do not
--                        (one exception, a body that took a new code, is in authored/tac_provider_successor.csv)
--   data_name_key        the name key the data sheet uses for the provider: its own name key, or the authored
--                        alias (authored/tac_name_alias.csv) where the sheet and the list name it differently
--   has_statement_data   data_name_key occurs in the statement rows of the same file
--   list_status          reported | excluded (the file says the accounts were not adopted in time) |
--                        acquired (the comment says there is no data for the year) | listed_without_data
--                        (listed, no data, no reason given)
-- The build stops when two providers of one file share a name key, because the data sheet names a provider by
-- text only and the join to the list would then repeat rows.

DROP TABLE IF EXISTS stg.tac_provider_year;
GO

CREATE TABLE stg.tac_provider_year (
    file_id             int            NOT NULL,
    source_row          int            NOT NULL,
    release             varchar(7)     NOT NULL,
    provider_type       varchar(30)    NOT NULL,
    provider_code       nvarchar(20)   NOT NULL,
    provider_name       nvarchar(300)  NOT NULL,
    name_key            nvarchar(400)  NOT NULL,
    data_name_key       nvarchar(400)  NOT NULL,
    region              nvarchar(100)  NOT NULL,
    sector              nvarchar(100)  NOT NULL,
    authorisation_date  nvarchar(40)   NOT NULL,
    comment_text        nvarchar(2000) NOT NULL,
    has_statement_data  bit            NOT NULL,
    list_status         varchar(25)    NOT NULL,
    CONSTRAINT pk_stg_tac_provider_year PRIMARY KEY (file_id, source_row)
);
GO

INSERT INTO stg.tac_provider_year
    (file_id, source_row, release, provider_type, provider_code, provider_name, name_key, data_name_key, region, sector,
     authorisation_date, comment_text, has_statement_data, list_status)
SELECT l.file_id, l.source_row, f.release, f.provider_type, UPPER(LTRIM(RTRIM(l.nhs_code))), l.provider_name,
       k.name_key, ISNULL(al.data_name_key, k.name_key), l.region, l.sector, l.authorisation_date, REPLACE(REPLACE(l.comments, CHAR(13), N' '), CHAR(10), N' '),
       x.has_data,
       CASE WHEN x.has_data = 1 THEN 'reported'
            WHEN l.comments LIKE N'%is excluded from this dataset%' THEN 'excluded'
            WHEN l.comments LIKE N'%there is no 20__/__ data%' THEN 'acquired'
            ELSE 'listed_without_data' END
FROM raw.tac_provider_list AS l
JOIN raw.tac_file AS f ON f.file_id = l.file_id
CROSS APPLY (SELECT stg.tac_name_key(l.provider_name) AS name_key) AS k
LEFT JOIN stg.tac_name_alias AS al ON al.release = f.release AND al.provider_code = UPPER(LTRIM(RTRIM(l.nhs_code)))
CROSS APPLY (SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM stg.tac_data_name AS n
                                            WHERE n.file_id = l.file_id AND n.name_key = ISNULL(al.data_name_key, k.name_key))
                              THEN 1 ELSE 0 END AS bit) AS has_data) AS x;
GO

IF EXISTS (SELECT 1 FROM stg.tac_provider_year GROUP BY file_id, name_key HAVING COUNT(*) > 1)
    THROW 50000, 'two providers of one TAC file share a name key', 1;
IF EXISTS (SELECT 1 FROM stg.tac_provider_year GROUP BY file_id, data_name_key HAVING COUNT(*) > 1)
    THROW 50000, 'two providers of one TAC file share a data name key', 1;
GO
