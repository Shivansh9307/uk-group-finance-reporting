-- scope: full
-- stg.tac_line_role, stg.tac_code_map, stg.tac_name_alias, stg.tac_provider_successor: typed copies of the four authored TAC files.
-- They hold no amount. The build stops, with a message, when a file breaks a rule.

DROP TABLE IF EXISTS stg.tac_name_alias;
GO
DROP TABLE IF EXISTS stg.tac_provider_successor;
GO
DROP TABLE IF EXISTS stg.tac_code_map;
GO
DROP TABLE IF EXISTS stg.tac_line_role;
GO

CREATE TABLE stg.tac_line_role (
    sub_code   varchar(20)    NOT NULL CONSTRAINT pk_stg_tac_line_role PRIMARY KEY,
    statement  varchar(4)     NOT NULL,
    section    nvarchar(60)   NOT NULL,
    line_kind  varchar(10)    NOT NULL,
    evidence   nvarchar(1000) NOT NULL,
    note       nvarchar(1000) NOT NULL
);
GO
CREATE TABLE stg.tac_code_map (
    old_sub_code      varchar(20)    NOT NULL CONSTRAINT pk_stg_tac_code_map PRIMARY KEY,
    current_sub_code  varchar(20)    NULL,
    change_kind       varchar(20)    NOT NULL,
    last_year_old     varchar(7)     NOT NULL,
    first_year_new    varchar(7)     NULL,
    evidence          nvarchar(2000) NOT NULL,
    note              nvarchar(2000) NOT NULL
);
GO
CREATE TABLE stg.tac_name_alias (
    release        varchar(7)     NOT NULL,
    provider_code  nvarchar(20)   NOT NULL,
    data_name      nvarchar(300)  NOT NULL,
    data_name_key  nvarchar(400)  NOT NULL,
    evidence       nvarchar(2000) NOT NULL,
    note           nvarchar(1000) NOT NULL,
    CONSTRAINT pk_stg_tac_name_alias PRIMARY KEY (release, provider_code)
);
GO
CREATE TABLE stg.tac_provider_successor (
    predecessor_code     nvarchar(20)   NOT NULL CONSTRAINT pk_stg_tac_provider_successor PRIMARY KEY,
    successor_code       nvarchar(20)   NOT NULL,
    change_kind          varchar(20)    NOT NULL,
    effective_date       date           NULL,
    quote_provider_code  nvarchar(20)   NOT NULL,
    quote_release        varchar(7)     NOT NULL,
    quote_fragment       nvarchar(1000) NOT NULL,
    evidence             nvarchar(2000) NOT NULL,
    note                 nvarchar(1000) NOT NULL
);
GO

IF EXISTS (SELECT 1 FROM authored.tac_provider_successor
           WHERE NULLIF(LTRIM(RTRIM(effective_date)), '') IS NOT NULL
             AND TRY_CAST(LTRIM(RTRIM(effective_date)) AS date) IS NULL)
    THROW 50000, 'authored/tac_provider_successor.csv: effective_date is not a date', 1;
GO

INSERT INTO stg.tac_line_role (sub_code, statement, section, line_kind, evidence, note)
SELECT LTRIM(RTRIM(sub_code)), LTRIM(RTRIM(statement)), LTRIM(RTRIM(section)), LTRIM(RTRIM(line_kind)), evidence, note
FROM authored.tac_line_role;
GO
INSERT INTO stg.tac_code_map (old_sub_code, current_sub_code, change_kind, last_year_old, first_year_new, evidence, note)
SELECT LTRIM(RTRIM(old_sub_code)), NULLIF(LTRIM(RTRIM(current_sub_code)), ''), LTRIM(RTRIM(change_kind)),
       LTRIM(RTRIM(last_year_old)), NULLIF(LTRIM(RTRIM(first_year_new)), ''), evidence, note
FROM authored.tac_code_map;
GO
INSERT INTO stg.tac_name_alias (release, provider_code, data_name, data_name_key, evidence, note)
SELECT LTRIM(RTRIM(release)), UPPER(LTRIM(RTRIM(provider_code))), LTRIM(RTRIM(data_name)),
       stg.tac_name_key(LTRIM(RTRIM(data_name))), evidence, note
FROM authored.tac_name_alias;
GO
INSERT INTO stg.tac_provider_successor
    (predecessor_code, successor_code, change_kind, effective_date, quote_provider_code, quote_release,
     quote_fragment, evidence, note)
SELECT LTRIM(RTRIM(predecessor_code)), LTRIM(RTRIM(successor_code)), LTRIM(RTRIM(change_kind)),
       TRY_CAST(NULLIF(LTRIM(RTRIM(effective_date)), '') AS date), LTRIM(RTRIM(quote_provider_code)),
       LTRIM(RTRIM(quote_release)), quote_fragment, evidence, note
FROM authored.tac_provider_successor;
GO

IF EXISTS (SELECT 1 FROM stg.tac_line_role WHERE line_kind NOT IN ('line', 'subtotal', 'total')
                                              OR statement NOT IN ('SoCI', 'SoFP', 'SoCF'))
    THROW 50000, 'authored/tac_line_role.csv: line_kind must be line, subtotal or total and statement SoCI, SoFP or SoCF', 1;
IF EXISTS (SELECT 1 FROM stg.tac_code_map WHERE change_kind NOT IN ('retired', 'relabelled'))
    THROW 50000, 'authored/tac_code_map.csv: change_kind must be retired or relabelled', 1;
IF EXISTS (SELECT 1 FROM stg.tac_provider_successor WHERE change_kind NOT IN ('acquired', 'merged', 'demised', 'new_code'))
    THROW 50000, 'authored/tac_provider_successor.csv: change_kind must be acquired, merged, demised or new_code', 1;
GO
