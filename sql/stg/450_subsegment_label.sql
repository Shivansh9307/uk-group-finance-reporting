-- stg.subsegment_label: the name of each sub-segment in each release, reduced for comparison.
--   One row per (release, sub_segment_code) that has non-zero rows in stg.inyear_snapshot.
--   label_norm  the published name with the leading 'CODE-' or 'CODE - ' removed, upper case, '&' read as
--               AND, every character that is not A-Z or 0-9 turned into a space, repeated spaces
--               collapsed. Two names with the same label_norm are the same name for the purpose of
--               following a sub-segment whose code stopped being used (dw.current_structure_line).
-- Names come from raw.oscar_inyear because the snapshot does not carry them; within one release a code
-- has one name (tested for dw.dim_segment).

DROP TABLE IF EXISTS stg.subsegment_label;
GO

CREATE TABLE stg.subsegment_label (
    release            varchar(7)     NOT NULL,
    release_seq        int            NOT NULL,
    sub_segment_code   nvarchar(50)   NOT NULL,
    sub_segment_name   nvarchar(1000) NOT NULL,
    label_norm         nvarchar(1000) NOT NULL,
    CONSTRAINT pk_stg_subsegment_label PRIMARY KEY (release, sub_segment_code)
);
GO

-- Normalise each distinct (code, name) once, then attach the result to every release that publishes it.
DROP TABLE IF EXISTS #names;
GO

SELECT n.sub_segment_code, n.sub_segment_name,
       REPLACE(UPPER(CASE WHEN UPPER(n.sub_segment_name) LIKE UPPER(n.sub_segment_code) + N'%'
                          THEN SUBSTRING(n.sub_segment_name, LEN(n.sub_segment_code) + 1, 1000)
                          ELSE n.sub_segment_name END), N'&', N' AND ') AS txt
INTO #names
FROM (SELECT DISTINCT sub_segment_code, sub_segment_name FROM raw.oscar_inyear) AS n;
GO

WITH tally AS (
    SELECT TOP (1000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i FROM sys.all_columns
), chars AS (
    SELECT s.sub_segment_code, s.sub_segment_name, t.i,
           CASE WHEN SUBSTRING(s.txt, t.i, 1) COLLATE Latin1_General_BIN2 LIKE N'[A-Z0-9]' THEN SUBSTRING(s.txt, t.i, 1) ELSE N' ' END AS ch
    FROM #names AS s
    JOIN tally AS t ON t.i <= LEN(s.txt)
), joined AS (
    SELECT sub_segment_code, sub_segment_name, STRING_AGG(CAST(ch AS nvarchar(max)), N'') WITHIN GROUP (ORDER BY i) AS txt
    FROM chars
    GROUP BY sub_segment_code, sub_segment_name
)
SELECT s.sub_segment_code, s.sub_segment_name,
       LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(j.txt, N''), N'  ', N' '), N'  ', N' '), N'  ', N' '), N'  ', N' '), N'  ', N' '))) AS label_norm
INTO #labels
FROM #names AS s
LEFT JOIN joined AS j ON j.sub_segment_code = s.sub_segment_code AND j.sub_segment_name = s.sub_segment_name;
GO

INSERT INTO stg.subsegment_label (release, release_seq, sub_segment_code, sub_segment_name, label_norm)
SELECT p.release, rel.release_seq, p.sub_segment_code, p.sub_segment_name, l.label_norm
FROM (
    SELECT r.release, r.sub_segment_code, MAX(r.sub_segment_name) AS sub_segment_name
    FROM raw.oscar_inyear AS r
    WHERE EXISTS (SELECT 1 FROM stg.inyear_snapshot AS s WHERE s.release = r.release AND s.sub_segment_code = r.sub_segment_code)
    GROUP BY r.release, r.sub_segment_code
) AS p
JOIN stg.release AS rel ON rel.release = p.release
JOIN #labels AS l ON l.sub_segment_code = p.sub_segment_code AND l.sub_segment_name = p.sub_segment_name;
GO
