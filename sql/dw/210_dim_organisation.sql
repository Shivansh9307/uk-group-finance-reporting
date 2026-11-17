-- dw.dim_organisation: Type 2 by release sequence, plus the Unknown member.
-- One row per version of an organisation (a durable key). A version starts when the organisation code, the
-- department (number or naming period) or the name really changes (stg.organisation_version_row, which
-- also states the alias rule for names). The versions of one key tile its life with no gap and no overlap:
-- a version runs from the first release it is reported in to the release before the next version starts;
-- the last one ends at the last release the key is reported in.
--   organisation_key   -1 = Unknown, then 1.. in (durable key, version) order
--   durable_key        the three-letter prefix, or the authored override (authored/organisation_key_override.csv)
--   durable_key_rule   'prefix' or the override's reason
--   department_key     the department (number and naming period) as the releases of this version report it
--   organisation_name  the display name: the spelling published in most releases of the version, the latest
--                      on a tie, unless the override sets display_name. Other spellings are in
--                      dw.organisation_name_alias.
--   version_reason     first release of the key, or the tracked attributes that changed
--   is_current         the key is reported in the latest release (this is its last version)
--   is_latest_version  the last version of the key, current or not
--   successor_durable_key  where the body went when it ended, if authored (a merger); otherwise NULL

DROP TABLE IF EXISTS dw.organisation_name_alias;
GO
DROP TABLE IF EXISTS dw.dim_organisation;
GO

CREATE TABLE dw.dim_organisation (
    organisation_key         int           NOT NULL CONSTRAINT pk_dw_dim_organisation PRIMARY KEY,
    durable_key              nvarchar(30)  NOT NULL,
    version_no               int           NOT NULL,
    organisation_code        nvarchar(50)  NOT NULL,
    organisation_name        nvarchar(400) NOT NULL,
    department_key           int           NOT NULL,
    valid_from_release_seq   int           NOT NULL,
    valid_to_release_seq     int           NOT NULL,
    valid_from_release       varchar(7)    NOT NULL,
    valid_to_release         varchar(7)    NOT NULL,
    n_releases_reported      int           NOT NULL,
    version_reason           varchar(80)   NOT NULL,
    change_code              bit           NOT NULL,
    change_department        bit           NOT NULL,
    change_department_move   bit           NOT NULL,   -- the department number changed (not only its naming period)
    change_name              bit           NOT NULL,
    durable_key_rule         varchar(30)   NOT NULL,
    successor_durable_key    nvarchar(30)  NULL,
    is_current               bit           NOT NULL,
    is_latest_version        bit           NOT NULL,
    CONSTRAINT uq_dw_dim_organisation_version UNIQUE (durable_key, version_no),
    CONSTRAINT fk_dw_dim_organisation_department FOREIGN KEY (department_key) REFERENCES dw.dim_department (department_key)
);
GO

INSERT INTO dw.dim_organisation
    (organisation_key, durable_key, version_no, organisation_code, organisation_name, department_key,
     valid_from_release_seq, valid_to_release_seq, valid_from_release, valid_to_release, n_releases_reported,
     version_reason, change_code, change_department, change_department_move, change_name, durable_key_rule,
     successor_durable_key, is_current, is_latest_version)
SELECT -1, N'UNKNOWN', 1, N'UNKNOWN', N'Unknown', -1, 1, m.release_seq, f.release, m.release, 0,
       'unknown member', 0, 0, 0, 0, 'unknown', NULL, 0, 1
FROM (SELECT TOP (1) release_seq, release FROM stg.release ORDER BY release_seq DESC) AS m
CROSS JOIN (SELECT TOP (1) release FROM stg.release ORDER BY release_seq) AS f;
GO

WITH v AS (
    SELECT durable_key, version_no,
           MIN(release_seq) AS first_seq, MAX(release_seq) AS last_seq, COUNT(*) AS n_releases,
           MIN(organisation_code) AS organisation_code,
           MIN(department_number) AS department_number, MIN(department_period_from_seq) AS department_period_from_seq,
           MAX(CAST(change_code AS int)) AS change_code, MAX(CAST(change_department AS int)) AS change_department,
           MAX(CAST(department_number_changed AS int)) AS change_department_move,
           MAX(CAST(change_name AS int)) AS change_name,
           MIN(key_rule) AS key_rule, MIN(successor_durable_key) AS successor_durable_key,
           MIN(display_name) AS display_name
    FROM stg.organisation_version_row
    GROUP BY durable_key, version_no
), k AS (
    SELECT durable_key, MAX(release_seq) AS key_last_seq FROM stg.organisation_version_row GROUP BY durable_key
), nm AS (
    SELECT durable_key, version_no, organisation_name COLLATE Latin1_General_BIN2 AS organisation_name,
           ROW_NUMBER() OVER (PARTITION BY durable_key, version_no
                              ORDER BY COUNT(*) DESC, MAX(release_seq) DESC, organisation_name COLLATE Latin1_General_BIN2) AS rk
    FROM stg.organisation_version_row
    GROUP BY durable_key, version_no, organisation_name COLLATE Latin1_General_BIN2
), w AS (
    SELECT v.*, k.key_last_seq,
           ISNULL(LEAD(v.first_seq) OVER (PARTITION BY v.durable_key ORDER BY v.version_no) - 1, k.key_last_seq) AS valid_to_seq,
           CASE WHEN LEAD(v.first_seq) OVER (PARTITION BY v.durable_key ORDER BY v.version_no) IS NULL THEN 1 ELSE 0 END AS is_last
    FROM v JOIN k ON k.durable_key = v.durable_key
)
INSERT INTO dw.dim_organisation
    (organisation_key, durable_key, version_no, organisation_code, organisation_name, department_key,
     valid_from_release_seq, valid_to_release_seq, valid_from_release, valid_to_release, n_releases_reported,
     version_reason, change_code, change_department, change_department_move, change_name, durable_key_rule,
     successor_durable_key, is_current, is_latest_version)
SELECT ROW_NUMBER() OVER (ORDER BY w.durable_key COLLATE Latin1_General_BIN2, w.version_no),
       w.durable_key, w.version_no, w.organisation_code, ISNULL(w.display_name, n.organisation_name), d.department_key,
       w.first_seq, w.valid_to_seq, f.release, t.release, w.n_releases,
       CAST(CASE WHEN w.version_no = 1 THEN 'first release of the key'
                 ELSE STUFF(CASE WHEN w.change_code = 1 THEN '; code change' ELSE '' END
                          + CASE WHEN w.change_department_move = 1 THEN '; department change'
                            WHEN w.change_department = 1 THEN '; department renamed' ELSE '' END
                          + CASE WHEN w.change_name = 1 THEN '; name change' ELSE '' END, 1, 2, '')
            END AS varchar(80)),
       CAST(w.change_code AS bit), CAST(w.change_department AS bit), CAST(w.change_department_move AS bit),
       CAST(w.change_name AS bit),
       w.key_rule, w.successor_durable_key,
       CAST(CASE WHEN w.is_last = 1 AND w.valid_to_seq = (SELECT MAX(release_seq) FROM stg.release) THEN 1 ELSE 0 END AS bit),
       CAST(w.is_last AS bit)
FROM w
JOIN nm AS n ON n.durable_key = w.durable_key AND n.version_no = w.version_no AND n.rk = 1
JOIN dw.dim_department AS d
  ON d.department_number = w.department_number AND d.valid_from_release_seq = w.department_period_from_seq
JOIN stg.release AS f ON f.release_seq = w.first_seq
JOIN stg.release AS t ON t.release_seq = w.valid_to_seq;
GO

-- Every spelling a version was published under, and whether it is the display name.
--   is_display_name        the spelling the display name was chosen from (an override's display_name is not
--                          a published spelling, so no row is flagged then).
--   same_name_as_display   1 where the spelling differs from the display name only in case, punctuation or
--                          bracketed tags (the same name_norm); 0 where it is a different name that
--                          alternates with it (an alias in the sense of the alias rule).
CREATE TABLE dw.organisation_name_alias (
    organisation_key       int           NOT NULL,
    organisation_name      nvarchar(400) COLLATE Latin1_General_BIN2 NOT NULL,   -- spellings that differ only in case are kept apart
    n_releases             int           NOT NULL,
    first_release_seq      int           NOT NULL,
    last_release_seq       int           NOT NULL,
    is_display_name        bit           NOT NULL,
    same_name_as_display   bit           NOT NULL,
    CONSTRAINT pk_dw_organisation_name_alias PRIMARY KEY (organisation_key, organisation_name),
    CONSTRAINT fk_dw_organisation_name_alias FOREIGN KEY (organisation_key) REFERENCES dw.dim_organisation (organisation_key)
);
GO

INSERT INTO dw.organisation_name_alias
    (organisation_key, organisation_name, n_releases, first_release_seq, last_release_seq, is_display_name, same_name_as_display)
SELECT o.organisation_key, g.organisation_name, g.n_releases, g.first_seq, g.last_seq,
       CAST(CASE WHEN g.organisation_name COLLATE Latin1_General_BIN2 = o.organisation_name COLLATE Latin1_General_BIN2
                 THEN 1 ELSE 0 END AS bit),
       CAST(CASE WHEN g.name_norm = dn.name_norm THEN 1 ELSE 0 END AS bit)
FROM (
    SELECT durable_key, version_no, organisation_name COLLATE Latin1_General_BIN2 AS organisation_name,
           MIN(name_norm) AS name_norm, COUNT(*) AS n_releases, MIN(release_seq) AS first_seq, MAX(release_seq) AS last_seq
    FROM stg.organisation_version_row
    GROUP BY durable_key, version_no, organisation_name COLLATE Latin1_General_BIN2
) AS g
JOIN dw.dim_organisation AS o ON o.durable_key = g.durable_key AND o.version_no = g.version_no
CROSS APPLY (
    SELECT TOP (1) r.name_norm FROM stg.organisation_version_row r
    WHERE r.durable_key = o.durable_key AND r.version_no = o.version_no
      AND r.organisation_name COLLATE Latin1_General_BIN2 = o.organisation_name COLLATE Latin1_General_BIN2
) AS dn;
GO
