-- One row per in-year release, from the files that were loaded.
--   release_seq: 1.. in publication order (first_published, then the release label).
--   financial_year / highest_period: from the staged rows of periods 1 and above.
--   version_label: the one Version value the release carries (a test asserts it is only one).

DROP TABLE IF EXISTS stg.release;
GO

CREATE TABLE stg.release (
    release           varchar(7)    NOT NULL CONSTRAINT pk_stg_release PRIMARY KEY,
    release_seq       int           NOT NULL,
    financial_year    varchar(7)    NOT NULL,
    first_published   date          NOT NULL,
    highest_period    tinyint       NOT NULL,
    version_label     nvarchar(400) NOT NULL,
    file_id           int           NOT NULL,
    CONSTRAINT uq_stg_release_seq UNIQUE (release_seq)
);
GO

INSERT INTO stg.release (release, release_seq, financial_year, first_published, highest_period, version_label, file_id)
SELECT
    f.release,
    ROW_NUMBER() OVER (ORDER BY CAST(LEFT(f.first_published, 10) AS date), f.release),
    s.financial_year,
    CAST(LEFT(f.first_published, 10) AS date),
    s.highest_period,
    v.version_label,
    f.file_id
FROM raw.oscar_inyear_file AS f
CROSS APPLY (
    SELECT MIN(x.financial_year) AS financial_year, MAX(x.period) AS highest_period
    FROM stg.inyear_snapshot AS x
    WHERE x.release = f.release AND x.period >= 1
) AS s
CROSS APPLY (
    SELECT MIN(r.version) AS version_label
    FROM raw.oscar_inyear AS r
    WHERE r.file_id = f.file_id
) AS v
WHERE f.primary_for_release = 'Y';
GO
