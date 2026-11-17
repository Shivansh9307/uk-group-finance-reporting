-- dw.dim_segment: one row per sub-segment code reported with a non-zero amount, plus the Unknown member (-1).
--   segment_name     the name published in the latest release that reports the code (within one release a
--                    code has one name: tested)
--   segment_label    the name without the leading 'CODE-' that most names carry
--   first_release / last_release   the first and last release with a non-zero row for the code
-- Codes that only ever carry zero-amount rows (47) are not here, because they have no fact row.

DROP TABLE IF EXISTS dw.dim_segment;
GO

CREATE TABLE dw.dim_segment (
    segment_key        int            NOT NULL CONSTRAINT pk_dw_dim_segment PRIMARY KEY,
    sub_segment_code   nvarchar(50)   NOT NULL,
    segment_name       nvarchar(1000) NOT NULL,
    segment_label      nvarchar(1000) NOT NULL,
    first_release      varchar(7)     NOT NULL,
    last_release       varchar(7)     NOT NULL,
    n_releases         int            NOT NULL,
    CONSTRAINT uq_dw_dim_segment_code UNIQUE (sub_segment_code)
);
GO

INSERT INTO dw.dim_segment (segment_key, sub_segment_code, segment_name, segment_label, first_release, last_release, n_releases)
VALUES (-1, N'UNK', N'Unknown', N'Unknown', '2019-03', '2019-03', 0);
GO

WITH span AS (
    SELECT sub_segment_code, MIN(release) AS first_release, MAX(release) AS last_release, COUNT(DISTINCT release) AS n_releases
    FROM stg.inyear_snapshot
    GROUP BY sub_segment_code
), nm AS (
    SELECT sp.sub_segment_code, MAX(r.sub_segment_name) AS segment_name
    FROM span AS sp
    JOIN raw.oscar_inyear AS r ON r.release = sp.last_release AND r.sub_segment_code = sp.sub_segment_code
    GROUP BY sp.sub_segment_code
)
INSERT INTO dw.dim_segment (segment_key, sub_segment_code, segment_name, segment_label, first_release, last_release, n_releases)
SELECT ROW_NUMBER() OVER (ORDER BY sp.sub_segment_code), sp.sub_segment_code, nm.segment_name,
       CASE WHEN nm.segment_name LIKE sp.sub_segment_code + N'-%'
            THEN LTRIM(SUBSTRING(nm.segment_name, LEN(sp.sub_segment_code) + 2, 1000)) ELSE nm.segment_name END,
       sp.first_release, sp.last_release, sp.n_releases
FROM span AS sp
JOIN nm ON nm.sub_segment_code = sp.sub_segment_code;
GO
