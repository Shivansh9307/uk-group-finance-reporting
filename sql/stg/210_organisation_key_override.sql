-- authored/organisation_key_override.csv, typed.
--   valid_from_seq / valid_to_seq   the releases the override covers; blank = unbounded.
--   durable_key        the key the code gets in those releases instead of its three-letter prefix.
--   merge_into_code    optional: in those releases the code is a second spelling of this code (a coding
--                      error), so it takes that code's version of the dimension.
--   successor_durable_key   optional: where the body went when it ended (a merger).
--   display_name       optional: the name shown for the versions in the override's releases, where the
--                      published names are wrong for the body (BEIS core is published as BIS).
-- An unknown release label stops the build.

DROP TABLE IF EXISTS stg.organisation_key_override;
GO

IF EXISTS (
    SELECT 1 FROM authored.organisation_key_override AS a
    WHERE (NULLIF(LTRIM(RTRIM(a.valid_from_release)), '') IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM stg.release r WHERE r.release = LTRIM(RTRIM(a.valid_from_release))))
       OR (NULLIF(LTRIM(RTRIM(a.valid_to_release)), '') IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM stg.release r WHERE r.release = LTRIM(RTRIM(a.valid_to_release))))
)
    THROW 50002, 'authored/organisation_key_override.csv names a release that does not exist', 1;
GO

CREATE TABLE stg.organisation_key_override (
    override_id            int            NOT NULL CONSTRAINT pk_stg_organisation_key_override PRIMARY KEY,  -- _load_order
    organisation_code      nvarchar(50)   NOT NULL,
    valid_from_seq         int            NOT NULL,
    valid_to_seq           int            NOT NULL,
    durable_key            nvarchar(30)   NOT NULL,
    merge_into_code        nvarchar(50)   NULL,
    successor_durable_key  nvarchar(30)   NULL,
    display_name           nvarchar(400)  NULL,
    reason                 varchar(30)    NOT NULL,
    evidence               nvarchar(max)  NOT NULL,
    note                   nvarchar(max)  NOT NULL
);
GO

INSERT INTO stg.organisation_key_override
    (override_id, organisation_code, valid_from_seq, valid_to_seq, durable_key, merge_into_code,
     successor_durable_key, display_name, reason, evidence, note)
SELECT a._load_order, LTRIM(RTRIM(a.organisation_code)),
       ISNULL(f.release_seq, 1),
       ISNULL(t.release_seq, (SELECT MAX(release_seq) FROM stg.release)),
       LTRIM(RTRIM(a.durable_key)),
       NULLIF(LTRIM(RTRIM(a.merge_into_code)), ''),
       NULLIF(LTRIM(RTRIM(a.successor_durable_key)), ''),
       NULLIF(LTRIM(RTRIM(a.display_name)), ''),
       LTRIM(RTRIM(a.reason)), a.evidence, a.note
FROM authored.organisation_key_override AS a
LEFT JOIN stg.release AS f ON f.release = NULLIF(LTRIM(RTRIM(a.valid_from_release)), '')
LEFT JOIN stg.release AS t ON t.release = NULLIF(LTRIM(RTRIM(a.valid_to_release)), '');
GO
