-- One row per organisation code and release, for the pairs that have non-zero rows in
-- stg.inyear_snapshot: the name and the department label the release publishes for that code.
--   organisation_prefix   the three letters; department_number   the last three digits of the code
--   (each department number carries one department label per release, see
--   docs/profiling/organisation-keys.md section 10, and a test proves it again on the loaded data).
--   name_norm   the name for comparison only: upper case, bracketed tags removed, punctuation and
--   repeated spaces collapsed. Two published names with the same name_norm are the same name; two names
--   with different name_norm may still be aliases of each other (decided in 230).
-- Names are read from raw.oscar_inyear because stg does not carry them. A release publishes one name and
-- one department label per code (a test checks that on raw).

DROP TABLE IF EXISTS stg.organisation_release;
GO

CREATE TABLE stg.organisation_release (
    release_seq          int           NOT NULL,
    release              varchar(7)    NOT NULL,
    organisation_code    nvarchar(50)  NOT NULL,
    organisation_prefix  nvarchar(3)   NOT NULL,
    department_number    nvarchar(10)  NOT NULL,
    organisation_name    nvarchar(400) NOT NULL,
    name_norm            nvarchar(400) NOT NULL,
    department_label     nvarchar(400) NOT NULL,
    CONSTRAINT pk_stg_organisation_release PRIMARY KEY (release_seq, organisation_code)
);
GO

INSERT INTO stg.organisation_release
    (release_seq, release, organisation_code, organisation_prefix, department_number,
     organisation_name, name_norm, department_label)
SELECT rel.release_seq, p.release, p.organisation_code, LEFT(p.organisation_code, 3), RIGHT(p.organisation_code, 3),
       n.organisation_name, UPPER(n.organisation_name), n.department_label
FROM (SELECT DISTINCT release, organisation_code FROM stg.inyear_snapshot) AS p
JOIN stg.release AS rel ON rel.release = p.release
JOIN (
    SELECT release, organisation_code,
           MIN(organisation_name) AS organisation_name, MIN(department_name) AS department_label
    FROM raw.oscar_inyear
    GROUP BY release, organisation_code
) AS n ON n.release = p.release AND n.organisation_code = p.organisation_code;
GO

-- Remove bracketed tags such as "(DFE022.GROUP) (OLD)" or "(ALB)" from the comparison name.
WHILE 1 = 1
BEGIN
    UPDATE stg.organisation_release
    SET name_norm = STUFF(name_norm, CHARINDEX('(', name_norm),
                          CHARINDEX(')', name_norm, CHARINDEX('(', name_norm)) - CHARINDEX('(', name_norm) + 1, '')
    WHERE CHARINDEX('(', name_norm) > 0 AND CHARINDEX(')', name_norm, CHARINDEX('(', name_norm)) > 0;
    IF @@ROWCOUNT = 0 BREAK;
END;
GO

UPDATE stg.organisation_release
SET name_norm = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
        REPLACE(name_norm, '&', ' AND '), ',', ' '), '.', ' '), ':', ' '), ';', ' '), '''', ' '),
        NCHAR(8217), ' '), '-', ' '), '/', ' '), '"', ' ');
GO

WHILE 1 = 1
BEGIN
    UPDATE stg.organisation_release SET name_norm = REPLACE(name_norm, '  ', ' ') WHERE name_norm LIKE '%  %';
    IF @@ROWCOUNT = 0 BREAK;
END;
GO

UPDATE stg.organisation_release SET name_norm = LTRIM(RTRIM(name_norm));
GO
