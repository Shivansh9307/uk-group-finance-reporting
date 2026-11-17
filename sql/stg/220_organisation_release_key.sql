-- The durable key of every organisation code in every release it is reported.
--   durable_key   the override's key where one covers the code and release, else the three-letter prefix.
--   key_rule      'prefix', or the override's reason.
--   effective_code   the code whose dimension version carries this row: the code itself, or merge_into_code.
--   is_merged_code   1 where effective_code differs from the code (a coding error, kept visible in the map).
--   department_period_from_seq   identifies the department naming period in force in the release.
-- Two overrides covering one code and release make the insert fail on the primary key, loudly.
-- A department number with no authored period in a release stops the build.

DROP TABLE IF EXISTS stg.organisation_release_key;
GO

IF EXISTS (
    SELECT 1 FROM stg.organisation_release AS r
    WHERE NOT EXISTS (SELECT 1 FROM stg.department_period d
                      WHERE d.department_number = r.department_number
                        AND r.release_seq BETWEEN d.valid_from_seq AND d.valid_to_seq)
)
    THROW 50003, 'a department number reported in a release has no period in authored/department_name.csv', 1;
GO

CREATE TABLE stg.organisation_release_key (
    release_seq                 int           NOT NULL,
    release                     varchar(7)    NOT NULL,
    organisation_code           nvarchar(50)  NOT NULL,
    organisation_prefix         nvarchar(3)   NOT NULL,
    department_number           nvarchar(10)  NOT NULL,
    organisation_name           nvarchar(400) NOT NULL,
    name_norm                   nvarchar(400) NOT NULL,
    department_period_from_seq  int           NOT NULL,
    durable_key                 nvarchar(30)  NOT NULL,
    key_rule                    varchar(30)   NOT NULL,
    override_id                 int           NULL,
    effective_code              nvarchar(50)  NOT NULL,
    is_merged_code              bit           NOT NULL,
    successor_durable_key       nvarchar(30)  NULL,
    display_name                nvarchar(400) NULL,
    CONSTRAINT pk_stg_organisation_release_key PRIMARY KEY (release_seq, organisation_code)
);
GO

INSERT INTO stg.organisation_release_key
    (release_seq, release, organisation_code, organisation_prefix, department_number, organisation_name,
     name_norm, department_period_from_seq, durable_key, key_rule, override_id, effective_code,
     is_merged_code, successor_durable_key, display_name)
SELECT r.release_seq, r.release, r.organisation_code, r.organisation_prefix, r.department_number,
       r.organisation_name, r.name_norm, d.valid_from_seq,
       ISNULL(o.durable_key, r.organisation_prefix),
       CAST(ISNULL(o.reason, 'prefix') AS varchar(30)),
       o.override_id,
       ISNULL(o.merge_into_code, r.organisation_code),
       CAST(CASE WHEN o.merge_into_code IS NOT NULL AND o.merge_into_code <> r.organisation_code THEN 1 ELSE 0 END AS bit),
       o.successor_durable_key, o.display_name
FROM stg.organisation_release AS r
JOIN stg.department_period AS d
  ON d.department_number = r.department_number AND r.release_seq BETWEEN d.valid_from_seq AND d.valid_to_seq
LEFT JOIN stg.organisation_key_override AS o
  ON o.organisation_code = r.organisation_code AND r.release_seq BETWEEN o.valid_from_seq AND o.valid_to_seq;
GO
