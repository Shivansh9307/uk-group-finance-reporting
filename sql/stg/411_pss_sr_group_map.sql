-- scope: full
-- stg.pss_sr_group_map: each Spending Review group name in the PSS database -> the OSCAR Spending Review group.
--   The match is on the name as written (exact), else through authored.pss_sr_group_alias (three names).
--   OSCAR group names come from the latest BUD vintage. match_method = exact | alias | unmatched; a test
--   fails if a PSS name is unmatched.

DROP TABLE IF EXISTS stg.pss_sr_group_map;
GO

CREATE TABLE stg.pss_sr_group_map (
    pss_sr_group_name  nvarchar(200) NOT NULL CONSTRAINT pk_stg_pss_sr_group_map PRIMARY KEY,
    sr_group_code      nvarchar(20)  NULL,
    sr_group_name      nvarchar(100) NULL,
    match_method       varchar(10)   NOT NULL
);
GO

WITH bud_groups AS (
    SELECT DISTINCT sr_group_code, sr_group_name
    FROM stg.bud_department_group_map
    WHERE is_latest_vintage = 1
), pss_names AS (
    SELECT DISTINCT sr_group_name FROM stg.pss_outturn
)
INSERT INTO stg.pss_sr_group_map (pss_sr_group_name, sr_group_code, sr_group_name, match_method)
SELECT n.sr_group_name,
       COALESCE(e.sr_group_code, a.sr_group_code),
       COALESCE(e.sr_group_name, a.sr_group_name),
       CASE WHEN e.sr_group_name IS NOT NULL THEN 'exact' WHEN a.sr_group_name IS NOT NULL THEN 'alias' ELSE 'unmatched' END
FROM pss_names AS n
LEFT JOIN bud_groups AS e ON e.sr_group_name = n.sr_group_name
LEFT JOIN authored.pss_sr_group_alias AS al ON al.pss_sr_group_name = n.sr_group_name
LEFT JOIN bud_groups AS a ON a.sr_group_name = al.bud_sr_group_name;
GO
