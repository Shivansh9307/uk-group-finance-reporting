-- dw.organisation_release_map: one row per organisation code and release that has rows in
-- stg.inyear_snapshot, with the dimension keys as THAT release reports them.
--   organisation_key   the version of the organisation (durable key) in force in the release. For a code
--                      that is a second spelling of another (EHR030 in June 2019) this is the version of
--                      the code it merges into; organisation_code in the dimension is then that code.
--   department_key     the department (number and naming period) the release reports for this code. It
--                      can differ from the version's department only for such a merged code.
-- The revision-delta fact joins on (release, organisation_code).

DROP TABLE IF EXISTS dw.organisation_release_map;
GO

CREATE TABLE dw.organisation_release_map (
    release            varchar(7)    NOT NULL,
    release_seq        int           NOT NULL,
    organisation_code  nvarchar(50)  NOT NULL,
    organisation_key   int           NOT NULL,
    department_key     int           NOT NULL,
    durable_key        nvarchar(30)  NOT NULL,
    CONSTRAINT pk_dw_organisation_release_map PRIMARY KEY (release, organisation_code),
    CONSTRAINT uq_dw_organisation_release_map_seq UNIQUE (release_seq, organisation_code),
    CONSTRAINT fk_dw_organisation_release_map_org FOREIGN KEY (organisation_key) REFERENCES dw.dim_organisation (organisation_key),
    CONSTRAINT fk_dw_organisation_release_map_dep FOREIGN KEY (department_key) REFERENCES dw.dim_department (department_key)
);
GO

INSERT INTO dw.organisation_release_map (release, release_seq, organisation_code, organisation_key, department_key, durable_key)
SELECT r.release, r.release_seq, r.organisation_code, o.organisation_key, d.department_key, r.durable_key
FROM stg.organisation_release_key AS r
JOIN dw.dim_organisation AS o
  ON o.durable_key = r.durable_key AND r.release_seq BETWEEN o.valid_from_release_seq AND o.valid_to_release_seq
JOIN dw.dim_department AS d
  ON d.department_number = r.department_number AND d.valid_from_release_seq = r.department_period_from_seq;
GO
