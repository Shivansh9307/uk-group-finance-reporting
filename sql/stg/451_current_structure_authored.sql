-- authored/current_structure_map.csv, typed: where I decided a line by hand.
--   durable_key                the organisation (dw.dim_organisation.durable_key); every version of it
--   sub_segment_code           a blank row applies to every sub-segment of the organisation that has no row
--                              of its own; a filled one to that sub-segment only
--   current_department_number  the department (three digits) or the Unallocated member ('U' and the number
--                              of the former department) the line belongs to in the current structure
--   decision                   what kind of decision it is, in a few words
--   review_set                 'beis_bud_2023_11' for the sub-segments the November 2023 annual file
--                              disagreed on; blank otherwise
--   is_estimated               1 only where the evidence is a judgement and not a published source
-- A number that is not a known department or Unallocated member stops the build: the file is mine, so a
-- typo should not load silently.

DROP TABLE IF EXISTS stg.current_structure_authored;
GO

IF EXISTS (
    SELECT 1 FROM authored.current_structure_map AS a
    WHERE NOT EXISTS (SELECT 1 FROM stg.department_period AS p WHERE p.department_number = LTRIM(RTRIM(a.current_department_number)))
)
    THROW 50002, 'authored/current_structure_map.csv names a department number that is not in authored/department_name.csv', 1;
GO

IF EXISTS (SELECT 1 FROM authored.current_structure_map AS a WHERE LTRIM(RTRIM(a.is_estimated)) NOT IN ('0', '1'))
    THROW 50003, 'authored/current_structure_map.csv: is_estimated must be 0 or 1', 1;
GO

CREATE TABLE stg.current_structure_authored (
    authored_row               int            NOT NULL CONSTRAINT pk_stg_current_structure_authored PRIMARY KEY,  -- _load_order
    durable_key                nvarchar(30)   NOT NULL,
    sub_segment_code           nvarchar(50)   NULL,
    current_department_number  nvarchar(10)   NOT NULL,
    decision                   nvarchar(200)  NOT NULL,
    review_set                 nvarchar(50)   NULL,
    is_estimated               bit            NOT NULL,
    evidence                   nvarchar(max)  NOT NULL,
    note                       nvarchar(max)  NOT NULL
);
GO

INSERT INTO stg.current_structure_authored
    (authored_row, durable_key, sub_segment_code, current_department_number, decision, review_set, is_estimated, evidence, note)
SELECT a._load_order, LTRIM(RTRIM(a.durable_key)), NULLIF(LTRIM(RTRIM(a.sub_segment_code)), ''),
       LTRIM(RTRIM(a.current_department_number)), LTRIM(RTRIM(a.decision)), NULLIF(LTRIM(RTRIM(a.review_set)), ''),
       CAST(LTRIM(RTRIM(a.is_estimated)) AS bit), a.evidence, a.note
FROM authored.current_structure_map AS a;
GO
