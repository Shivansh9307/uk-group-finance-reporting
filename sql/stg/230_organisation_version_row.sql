-- Where does a new version of an organisation start?
-- One row per durable key and release (the rows whose code is its own effective code), with a flag for
-- each tracked attribute that changed since the previous release the key was reported in:
--   change_code         the organisation code differs (a move between departments changes the numeric
--                       suffix, so this is how a move shows when the prefix is the durable key)
--   change_department   the department number or its naming period differs (a move, or the department's
--                       real rename; label flips are not in the data at this level, see dim_department)
--   change_name         a REAL name change, see below
-- A version starts at the first row of a key and at every row with at least one flag.
--
-- Alias rule for names. Published names flip between spellings from release to release (40 alternations
-- in the profile). A change from name X to name Y (compared as name_norm) at release r is a real change
-- only if X is never published again after r AND Y was never published before r. If X comes back later,
-- or Y was seen earlier, the two are aliases of one name and nothing is versioned. Case, punctuation and
-- bracketed tags never matter (name_norm). A rename that is later reverted is therefore treated as an
-- alias; departments, where that happens for real (DLUHC back to MHCLG), are authored by hand instead.

DROP TABLE IF EXISTS stg.organisation_version_row;
GO

CREATE TABLE stg.organisation_version_row (
    durable_key                 nvarchar(30)  NOT NULL,
    release_seq                 int           NOT NULL,
    organisation_code           nvarchar(50)  NOT NULL,
    department_number           nvarchar(10)  NOT NULL,
    department_period_from_seq  int           NOT NULL,
    organisation_name           nvarchar(400) NOT NULL,
    name_norm                   nvarchar(400) NOT NULL,
    key_rule                    varchar(30)   NOT NULL,
    successor_durable_key       nvarchar(30)  NULL,
    display_name                nvarchar(400) NULL,
    change_code                 bit           NOT NULL,
    change_department           bit           NOT NULL,
    department_number_changed   bit           NOT NULL,   -- change_department and the number itself differs (a move)
    change_name                 bit           NOT NULL,
    version_no                  int           NOT NULL,   -- 1.. within the durable key
    CONSTRAINT pk_stg_organisation_version_row PRIMARY KEY (durable_key, release_seq)
);
GO

INSERT INTO stg.organisation_version_row
    (durable_key, release_seq, organisation_code, department_number, department_period_from_seq,
     organisation_name, name_norm, key_rule, successor_durable_key, display_name,
     change_code, change_department, department_number_changed, change_name, version_no)
SELECT f.durable_key, f.release_seq, f.organisation_code, f.department_number, f.department_period_from_seq,
       f.organisation_name, f.name_norm, f.key_rule, f.successor_durable_key, f.display_name,
       f.change_code, f.change_department, f.department_number_changed, f.change_name,
       SUM(CASE WHEN f.prev_seq IS NULL OR f.change_code = 1 OR f.change_department = 1 OR f.change_name = 1
                THEN 1 ELSE 0 END)
           OVER (PARTITION BY f.durable_key ORDER BY f.release_seq ROWS UNBOUNDED PRECEDING)
FROM (
    SELECT l.*,
        CAST(CASE WHEN l.prev_seq IS NOT NULL AND l.organisation_code <> l.prev_code THEN 1 ELSE 0 END AS bit) AS change_code,
        CAST(CASE WHEN l.prev_seq IS NOT NULL
                   AND (l.department_number <> l.prev_dept OR l.department_period_from_seq <> l.prev_dept_from)
                  THEN 1 ELSE 0 END AS bit) AS change_department,
        CAST(CASE WHEN l.prev_seq IS NOT NULL AND l.department_number <> l.prev_dept THEN 1 ELSE 0 END AS bit)
            AS department_number_changed,
        CAST(CASE WHEN l.prev_seq IS NOT NULL AND l.name_norm <> l.prev_name_norm
                   AND NOT EXISTS (SELECT 1 FROM stg.organisation_release_key x
                                   WHERE x.durable_key = l.durable_key AND x.is_merged_code = 0
                                     AND x.release_seq > l.release_seq AND x.name_norm = l.prev_name_norm)
                   AND NOT EXISTS (SELECT 1 FROM stg.organisation_release_key x
                                   WHERE x.durable_key = l.durable_key AND x.is_merged_code = 0
                                     AND x.release_seq < l.release_seq AND x.name_norm = l.name_norm)
                  THEN 1 ELSE 0 END AS bit) AS change_name
    FROM (
        SELECT b.durable_key, b.release_seq, b.organisation_code, b.department_number,
               b.department_period_from_seq, b.organisation_name, b.name_norm, b.key_rule,
               b.successor_durable_key, b.display_name,
               LAG(b.release_seq) OVER (PARTITION BY b.durable_key ORDER BY b.release_seq) AS prev_seq,
               LAG(b.organisation_code) OVER (PARTITION BY b.durable_key ORDER BY b.release_seq) AS prev_code,
               LAG(b.department_number) OVER (PARTITION BY b.durable_key ORDER BY b.release_seq) AS prev_dept,
               LAG(b.department_period_from_seq) OVER (PARTITION BY b.durable_key ORDER BY b.release_seq) AS prev_dept_from,
               LAG(b.name_norm) OVER (PARTITION BY b.durable_key ORDER BY b.release_seq) AS prev_name_norm
        FROM stg.organisation_release_key AS b
        WHERE b.is_merged_code = 0
    ) AS l
) AS f;
GO
