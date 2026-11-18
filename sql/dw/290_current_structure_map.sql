-- stg.current_structure_map: which department each (organisation version, sub-segment) belongs to in the
-- CURRENT structure. The view keeps the column contract that dw.fact_outturn reads:
--   organisation_key         dw.dim_organisation
--   sub_segment_code         as published
--   current_department_key   dw.dim_department: a department that exists now, or an Unallocated member
--   method                   the rule that decided the line (below)
--   is_estimated             1 where an authored row rests on a judgement and not on a published source
-- It reads dw.current_structure_line, which holds the same rows with the evidence (the former department,
-- the authored row, the release and code the rule matched). Both are in this file because they read dw
-- tables and the runner builds a layer's files in order. Covers every (organisation_key, sub_segment_code)
-- pair in stg.inyear_snapshot exactly once. There is no weighting and no split: a line has one department.
--
-- Definitions
--   current department  a dim_department period with is_current = 1, or an Unallocated member, or a period
--                       that is the last of its department number and whose number is reported in the latest
--                       year-end release. The last clause exists because the newest release (September) is
--                       partial: three bodies that report in June (National Audit Office, Crown Estate Office,
--                       Judicial Pensions Scheme) are not in it, and is_current marks them not current.
--   current form        of a department period: itself when it is a current department, otherwise the latest
--                       current period of the same number (DLUHC and the old DCMS name become MHCLG and DCMS).
--                       A number whose core code was reused for a different department (authored override
--                       reason reused_code: 013, 030, 084) has no current form for its earlier period.
--   home                the organisation's own department, taken from the latest version of its durable key,
--                       has a current form. An organisation without a home is one whose department was closed
--                       or split (BEIS core, DIT, DFID, FCO, DExEU and a few bodies that closed with them).
--
-- Rules, in this order; the first that gives a department decides the line
--   authored line          a row of authored/current_structure_map.csv for the durable key and sub-segment
--   (the next two only for an organisation without a home: for an organisation that has a home the code
--   rule would send a few lines to a department that only reported the code in its last release, which I
--   checked and rejected, see docs/data-dictionary/current-structure.md)
--   sub-segment code       the code was still published after the organisation's last release: the current
--                          form of the department that published it in the latest release that has it
--   sub-segment name       the code stopped, but the same name (leading code removed, see
--                          stg.subsegment_label) is published under another code after the code's last
--                          release: the current form of the one department that publishes it in the latest
--                          such release (a name found in two departments does not decide)
--   authored organisation  a row of the file for the durable key with a blank sub-segment
--   organisation current   the current form of the department of the durable key's latest version (the
--   department             default rule of the first version of this view)
--   organisation successor the current form of the department of successor_durable_key's latest version
--   unallocated former     the Unallocated member of the former department ('U' and its number in
--   department             authored/department_name.csv)
-- For an organisation with a home, an authored organisation row wins over its own department; otherwise the
-- order is the one above.

DROP VIEW IF EXISTS stg.current_structure_map;
GO
DROP TABLE IF EXISTS dw.current_structure_line;
GO
DROP TABLE IF EXISTS dw.current_structure_organisation;
GO
DROP TABLE IF EXISTS dw.current_structure_department;
GO

-- dw.current_structure_department: every department period, whether it counts as a current department
-- (is_live) and its current form (NULL when it has none).
CREATE TABLE dw.current_structure_department (
    department_key       int           NOT NULL CONSTRAINT pk_dw_current_structure_department PRIMARY KEY,
    department_number    nvarchar(10)  NOT NULL,
    member_type          varchar(20)   NOT NULL,
    is_live              bit           NOT NULL,
    current_form_key     int           NULL
);
GO

-- dw.current_structure_organisation: each durable key with the department of its latest version (the
-- former department), the current form of it (the home, NULL for an organisation without one) and the
-- current form of its successor's department.
CREATE TABLE dw.current_structure_organisation (
    durable_key             nvarchar(30)  NOT NULL CONSTRAINT pk_dw_current_structure_organisation PRIMARY KEY,
    former_department_key   int           NOT NULL,
    home_department_key     int           NULL,
    successor_department_key int          NULL,
    last_release_seq        int           NOT NULL
);
GO

CREATE TABLE dw.current_structure_line (
    organisation_key        int           NOT NULL,
    sub_segment_code        nvarchar(50)  NOT NULL,
    durable_key             nvarchar(30)  NOT NULL,
    former_department_key   int           NOT NULL,   -- department of the durable key's latest version, as reported
    current_department_key  int           NOT NULL,
    method                  varchar(40)   NOT NULL,
    is_estimated            bit           NOT NULL,
    authored_row            int           NULL,       -- _load_order in authored/current_structure_map.csv
    matched_release         varchar(7)    NULL,       -- the release the code or the name was found in (code and name rules)
    matched_code            nvarchar(50)  NULL,       -- the code that carries the name now (name rule)
    rule_department_key     int           NULL,       -- for an authored line: the department the rules alone would give
    rule_method             varchar(40)   NULL,       -- and the rule that gives it
    CONSTRAINT pk_dw_current_structure_line PRIMARY KEY (organisation_key, sub_segment_code)
);
GO

DECLARE @latest int = (SELECT MAX(release_seq) FROM stg.release);
DECLARE @latest_ye int = (SELECT MAX(release_seq) FROM stg.release WHERE highest_period = 12);

-- 1. departments: current or not, and their current form
DROP TABLE IF EXISTS #dept;
SELECT d.department_key, d.department_number, d.member_type, d.valid_from_release_seq,
       CAST(CASE WHEN d.is_current = 1
                   OR (d.member_type = 'Department' AND d.valid_to_release_seq = @latest
                       AND EXISTS (SELECT 1 FROM stg.organisation_release r
                                   WHERE r.release_seq = @latest_ye AND r.department_number = d.department_number))
                 THEN 1 ELSE 0 END AS bit) AS is_live
INTO #dept
FROM dw.dim_department AS d;

DROP TABLE IF EXISTS #form;
SELECT d.department_key,
       CASE WHEN d.is_live = 1 THEN d.department_key
            WHEN d.member_type = 'Department'
             AND NOT EXISTS (SELECT 1 FROM stg.organisation_key_override o
                             WHERE o.reason = 'reused_code' AND RIGHT(o.organisation_code, 3) = d.department_number)
            THEN (SELECT TOP (1) x.department_key FROM #dept x
                  WHERE x.department_number = d.department_number AND x.is_live = 1
                    AND x.valid_from_release_seq > d.valid_from_release_seq
                  ORDER BY x.valid_from_release_seq DESC)
       END AS form_key
INTO #form
FROM #dept AS d;

DROP TABLE IF EXISTS #numkey;      -- a number written in the authored files -> the live period of it
SELECT d.department_number, (SELECT TOP (1) x.department_key FROM #dept x
                             WHERE x.department_number = d.department_number AND x.is_live = 1
                             ORDER BY x.valid_from_release_seq DESC) AS department_key
INTO #numkey
FROM (SELECT DISTINCT department_number FROM #dept) AS d;

-- 2. organisations (durable keys)
DROP TABLE IF EXISTS #org;
SELECT l.durable_key, l.department_key AS former_department_key, f.form_key AS own_form, l.valid_to_release_seq AS org_last_seq,
       sf.form_key AS successor_form, fd.department_number AS former_number
INTO #org
FROM dw.dim_organisation AS l
JOIN #form AS f ON f.department_key = l.department_key
JOIN dw.dim_department AS fd ON fd.department_key = l.department_key
LEFT JOIN dw.dim_organisation AS s ON s.durable_key = l.successor_durable_key AND s.is_latest_version = 1
LEFT JOIN #form AS sf ON sf.department_key = s.department_key
WHERE l.is_latest_version = 1;

INSERT INTO dw.current_structure_department (department_key, department_number, member_type, is_live, current_form_key)
SELECT d.department_key, d.department_number, d.member_type, d.is_live, f.form_key
FROM #dept AS d JOIN #form AS f ON f.department_key = d.department_key;

INSERT INTO dw.current_structure_organisation (durable_key, former_department_key, home_department_key, successor_department_key, last_release_seq)
SELECT durable_key, former_department_key, own_form, successor_form, org_last_seq FROM #org;

-- 3. authored rows
DROP TABLE IF EXISTS #auth;
SELECT a.authored_row, a.durable_key, a.sub_segment_code, k.department_key, a.is_estimated
INTO #auth
FROM stg.current_structure_authored AS a
JOIN #numkey AS k ON k.department_number = a.current_department_number;

-- 4. the lines
DROP TABLE IF EXISTS #pair;
SELECT p.organisation_key, p.sub_segment_code, o.durable_key
INTO #pair
FROM (
    SELECT DISTINCT m.organisation_key, s.sub_segment_code
    FROM stg.inyear_snapshot AS s
    JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
) AS p
JOIN dw.dim_organisation AS o ON o.organisation_key = p.organisation_key;

-- 5. the code rule: the latest release that publishes the code, and the one department that publishes it there
DROP TABLE IF EXISTS #code_last;
SELECT s.sub_segment_code, l.last_seq, r.release AS last_release,
       CASE WHEN COUNT(DISTINCT m.department_key) = 1 THEN MAX(f.form_key) END AS form_key
INTO #code_last
FROM (SELECT s.sub_segment_code, MAX(r.release_seq) AS last_seq
      FROM stg.inyear_snapshot AS s JOIN stg.release AS r ON r.release = s.release GROUP BY s.sub_segment_code) AS l
JOIN stg.release AS r ON r.release_seq = l.last_seq
JOIN stg.inyear_snapshot AS s ON s.release = r.release AND s.sub_segment_code = l.sub_segment_code
JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
JOIN #form AS f ON f.department_key = m.department_key
GROUP BY s.sub_segment_code, l.last_seq, r.release;

-- 6. the name rule: for each code, the latest later release that publishes its name under another code
--    in a department that has a current form
DROP TABLE IF EXISTS #name_pub;     -- (name, release, code) published in a department with a current form
SELECT DISTINCT h.label_norm, h.release_seq, h.release, h.sub_segment_code, f.form_key
INTO #name_pub
FROM stg.subsegment_label AS h
JOIN stg.inyear_snapshot AS s ON s.release = h.release AND s.sub_segment_code = h.sub_segment_code
JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
JOIN #form AS f ON f.department_key = m.department_key AND f.form_key IS NOT NULL;

DROP TABLE IF EXISTS #name_hit;
SELECT c.sub_segment_code, h.release_seq AS hit_seq, h.release AS hit_release,
       MIN(h.sub_segment_code) AS hit_code,
       COUNT(DISTINCT h.form_key) AS n_forms, MAX(h.form_key) AS form_key
INTO #name_hit
FROM #code_last AS c
JOIN stg.subsegment_label AS own ON own.sub_segment_code = c.sub_segment_code AND own.release_seq = c.last_seq
JOIN #name_pub AS h ON h.label_norm = own.label_norm AND h.sub_segment_code <> c.sub_segment_code AND h.release_seq > c.last_seq
WHERE h.release_seq = (
    SELECT MAX(h2.release_seq) FROM #name_pub AS h2
    WHERE h2.label_norm = own.label_norm AND h2.sub_segment_code <> c.sub_segment_code AND h2.release_seq > c.last_seq)
GROUP BY c.sub_segment_code, h.release_seq, h.release;

DROP TABLE IF EXISTS #cand;
SELECT p.organisation_key, p.sub_segment_code, p.durable_key, o.former_department_key, v.rank_no, v.department_key, v.method,
       v.is_estimated, v.authored_row, v.matched_release, v.matched_code
INTO #cand
FROM #pair AS p
JOIN #org AS o ON o.durable_key = p.durable_key
LEFT JOIN #auth AS al ON al.durable_key = p.durable_key AND al.sub_segment_code = p.sub_segment_code
LEFT JOIN #auth AS ao ON ao.durable_key = p.durable_key AND ao.sub_segment_code IS NULL
LEFT JOIN #code_last AS cl ON cl.sub_segment_code = p.sub_segment_code
LEFT JOIN #name_hit AS nh ON nh.sub_segment_code = p.sub_segment_code AND nh.n_forms = 1
LEFT JOIN #numkey AS un ON un.department_number = N'U' + o.former_number
CROSS APPLY (VALUES
    (1, al.department_key, 'authored line', al.is_estimated, al.authored_row, CAST(NULL AS varchar(7)), CAST(NULL AS nvarchar(50))),
    (2, CASE WHEN o.own_form IS NOT NULL THEN ao.department_key END, 'authored organisation', ao.is_estimated, ao.authored_row, NULL, NULL),
    (3, CASE WHEN o.own_form IS NULL AND cl.last_seq > o.org_last_seq THEN cl.form_key END, 'sub-segment code', CAST(0 AS bit), NULL, cl.last_release, NULL),
    (4, CASE WHEN o.own_form IS NULL THEN nh.form_key END, 'sub-segment name', CAST(0 AS bit), NULL, nh.hit_release, nh.hit_code),
    (5, CASE WHEN o.own_form IS NULL THEN ao.department_key END, 'authored organisation', ao.is_estimated, ao.authored_row, NULL, NULL),
    (6, o.own_form, 'organisation current department', CAST(0 AS bit), NULL, NULL, NULL),
    (7, o.successor_form, 'organisation successor', CAST(0 AS bit), NULL, NULL, NULL),
    (8, un.department_key, 'unallocated former department', CAST(0 AS bit), NULL, NULL, NULL)
) AS v(rank_no, department_key, method, is_estimated, authored_row, matched_release, matched_code)
WHERE v.department_key IS NOT NULL;

DROP TABLE IF EXISTS #top;
SELECT *, ROW_NUMBER() OVER (PARTITION BY organisation_key, sub_segment_code ORDER BY rank_no) AS rn
INTO #top
FROM #cand;

INSERT INTO dw.current_structure_line
    (organisation_key, sub_segment_code, durable_key, former_department_key, current_department_key, method,
     is_estimated, authored_row, matched_release, matched_code, rule_department_key, rule_method)
SELECT p.organisation_key, p.sub_segment_code, p.durable_key, o.former_department_key,
       ISNULL(t1.department_key, -1), ISNULL(t1.method, 'unresolved'), ISNULL(t1.is_estimated, 0), t1.authored_row,
       t1.matched_release, t1.matched_code,
       CASE WHEN t1.rank_no = 1 THEN t2.department_key END, CASE WHEN t1.rank_no = 1 THEN t2.method END
FROM #pair AS p
JOIN #org AS o ON o.durable_key = p.durable_key
LEFT JOIN #top AS t1 ON t1.organisation_key = p.organisation_key AND t1.sub_segment_code = p.sub_segment_code AND t1.rn = 1
LEFT JOIN #top AS t2 ON t2.organisation_key = p.organisation_key AND t2.sub_segment_code = p.sub_segment_code AND t2.rn = 2;
GO

CREATE VIEW stg.current_structure_map
AS
SELECT organisation_key, sub_segment_code, current_department_key, method, is_estimated
FROM dw.current_structure_line;
GO
