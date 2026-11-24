-- scope: full
-- stg.workforce_org_map: authored.workforce_org_map, typed. AUTHORED data: a decision I made by reading each published
-- name against the organisation dimension; it is not source data and never part of a real total on its own.
--   dept         the series of the file that publishes the name (dft, defra, mod ...), as in the release label
--   name_key     the published name reduced as stg.workforce_name_key reduces it
--   valid_from, valid_to   first and last month (inclusive) the decision covers; an empty bound is open
--   decision     map = the name is the organisation `durable_key`; exclude = I reviewed it and it has no OSCAR
--                organisation of its own (the `reason` says why); the rows are quarantined, not dropped
--   durable_key  the durable key of dw.dim_organisation (decision = map only)
--   basis        why: name (same name as the OSCAR organisation) | name_variant (another spelling or an earlier or later
--                name of the same body) | agency_into_parent (an executive agency with no OSCAR organisation of its own,
--                counted in its parent department's organisation; an assumption, see the data dictionary) | part_of (a body
--                that is part of the OSCAR organisation, such as a research council in UKRI)

DROP TABLE IF EXISTS stg.workforce_org_map;
GO

SELECT CAST(a._load_order AS int) AS map_id,
       CAST(LTRIM(RTRIM(a.dept)) AS varchar(20)) AS dept,
       CAST(a.organisation_name AS nvarchar(400)) AS organisation_name,
       k.name_key,
       TRY_CAST(CONCAT(NULLIF(LTRIM(RTRIM(a.valid_from)), ''), '-01') AS date) AS valid_from,
       TRY_CAST(CONCAT(NULLIF(LTRIM(RTRIM(a.valid_to)), ''), '-01') AS date) AS valid_to,
       CAST(LTRIM(RTRIM(a.decision)) AS varchar(10)) AS decision,
       CAST(NULLIF(LTRIM(RTRIM(a.durable_key)), '') AS varchar(20)) AS durable_key,
       CAST(NULLIF(LTRIM(RTRIM(a.basis)), '') AS varchar(30)) AS basis,
       CAST(a.reason AS nvarchar(400)) AS reason,
       CAST(a.note AS nvarchar(1000)) AS note
INTO stg.workforce_org_map
FROM authored.workforce_org_map AS a
CROSS APPLY stg.workforce_name_key(a.organisation_name) AS k;
GO

ALTER TABLE stg.workforce_org_map ALTER COLUMN map_id int NOT NULL;
GO

ALTER TABLE stg.workforce_org_map ADD CONSTRAINT pk_stg_workforce_org_map PRIMARY KEY (map_id);
GO
