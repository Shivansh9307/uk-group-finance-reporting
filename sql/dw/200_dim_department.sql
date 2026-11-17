-- dw.dim_department: one row per department number and naming period, plus the Unknown member.
-- Built from authored/department_name.csv (stg.department_period). The key is the three-digit number;
-- the published department name is a label that alternates between releases and is never a key.
--   department_key   -1 = Unknown, then 1.. in (department number, period start) order
--   member_type      Department | Unallocated | Unknown. Unallocated members are added by an authored CSV
--                    row (a later task); nothing else in this table changes for them.
--   valid_*          release sequence (1 = March 2019) and label; an open period ends at the latest release
--   is_current       the period covers the latest release, and for a Department the number is reported in
--                    it, so a department that has stopped being reported is not current

-- Tables that point at it are dropped first, so a rebuild into an existing database works.
DROP TABLE IF EXISTS dw.organisation_release_map;
GO
DROP TABLE IF EXISTS dw.organisation_name_alias;
GO
DROP TABLE IF EXISTS dw.dim_organisation;
GO
DROP TABLE IF EXISTS dw.dim_department;
GO

CREATE TABLE dw.dim_department (
    department_key          int           NOT NULL CONSTRAINT pk_dw_dim_department PRIMARY KEY,
    department_number       nvarchar(10)  NOT NULL,
    department_name         nvarchar(400) NOT NULL,
    member_type             varchar(20)   NOT NULL,
    valid_from_release_seq  int           NOT NULL,
    valid_to_release_seq    int           NOT NULL,
    valid_from_release      varchar(7)    NOT NULL,
    valid_to_release        varchar(7)    NOT NULL,
    is_current              bit           NOT NULL,
    CONSTRAINT uq_dw_dim_department_period UNIQUE (department_number, valid_from_release_seq)
);
GO

INSERT INTO dw.dim_department
    (department_key, department_number, department_name, member_type, valid_from_release_seq,
     valid_to_release_seq, valid_from_release, valid_to_release, is_current)
SELECT -1, N'UNK', N'Unknown', 'Unknown', 1, m.release_seq, f.release, m.release, 0
FROM (SELECT TOP (1) release_seq, release FROM stg.release ORDER BY release_seq DESC) AS m
CROSS JOIN (SELECT TOP (1) release FROM stg.release ORDER BY release_seq) AS f;
GO

INSERT INTO dw.dim_department
    (department_key, department_number, department_name, member_type, valid_from_release_seq,
     valid_to_release_seq, valid_from_release, valid_to_release, is_current)
SELECT ROW_NUMBER() OVER (ORDER BY p.department_number, p.valid_from_seq),
       p.department_number, p.department_name, p.member_type, p.valid_from_seq, p.valid_to_seq,
       f.release, t.release,
       CAST(CASE WHEN p.valid_to_seq = m.latest_seq
                  AND (p.member_type <> 'Department'
                       OR EXISTS (SELECT 1 FROM stg.organisation_release r
                                  WHERE r.release_seq = m.latest_seq AND r.department_number = p.department_number))
                 THEN 1 ELSE 0 END AS bit)
FROM stg.department_period AS p
JOIN stg.release AS f ON f.release_seq = p.valid_from_seq
JOIN stg.release AS t ON t.release_seq = p.valid_to_seq
CROSS JOIN (SELECT MAX(release_seq) AS latest_seq FROM stg.release) AS m;
GO
