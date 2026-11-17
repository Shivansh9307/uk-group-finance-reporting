-- authored/department_name.csv, typed: one row per department number and naming period.
--   valid_from_seq / valid_to_seq   release sequence numbers; a blank from means the first release,
--   a blank to means open ended (the latest release).
--   member_type   Department (the default) or Unallocated; Unknown is added by dw.dim_department itself.
-- An unknown release label stops the build: the file is mine, so a typo should not load silently.

DROP TABLE IF EXISTS stg.department_period;
GO

IF EXISTS (
    SELECT 1 FROM authored.department_name AS a
    WHERE (NULLIF(LTRIM(RTRIM(a.valid_from_release)), '') IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM stg.release r WHERE r.release = LTRIM(RTRIM(a.valid_from_release))))
       OR (NULLIF(LTRIM(RTRIM(a.valid_to_release)), '') IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM stg.release r WHERE r.release = LTRIM(RTRIM(a.valid_to_release))))
)
    THROW 50001, 'authored/department_name.csv names a release that does not exist', 1;
GO

CREATE TABLE stg.department_period (
    department_number  nvarchar(10)   NOT NULL,
    valid_from_seq     int            NOT NULL,
    valid_to_seq       int            NOT NULL,
    department_name    nvarchar(400)  NOT NULL,
    member_type        varchar(20)    NOT NULL,
    published_labels   nvarchar(max)  NOT NULL,   -- labels the files use in the period, separated by ' | '
    evidence           nvarchar(max)  NOT NULL,
    note               nvarchar(max)  NOT NULL,
    authored_row       int            NOT NULL,   -- _load_order in authored.department_name
    CONSTRAINT pk_stg_department_period PRIMARY KEY (department_number, valid_from_seq)
);
GO

INSERT INTO stg.department_period
    (department_number, valid_from_seq, valid_to_seq, department_name, member_type, published_labels,
     evidence, note, authored_row)
SELECT LTRIM(RTRIM(a.department_number)),
       ISNULL(f.release_seq, 1),
       ISNULL(t.release_seq, (SELECT MAX(release_seq) FROM stg.release)),
       LTRIM(RTRIM(a.department_name)),
       ISNULL(NULLIF(LTRIM(RTRIM(a.member_type)), ''), 'Department'),
       a.published_labels, a.evidence, a.note, a._load_order
FROM authored.department_name AS a
LEFT JOIN stg.release AS f ON f.release = NULLIF(LTRIM(RTRIM(a.valid_from_release)), '')
LEFT JOIN stg.release AS t ON t.release = NULLIF(LTRIM(RTRIM(a.valid_to_release)), '');
GO
