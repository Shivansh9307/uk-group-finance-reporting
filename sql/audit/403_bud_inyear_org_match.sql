-- scope: full
-- audit.bud_inyear_org_match: the organisation codes of the newest in-year release against the organisation list
-- of the newest BUD vintage. A code that is in the in-year release and not in the BUD is reported here with its
-- in-year amount and stays in stg.inyear_snapshot: nothing is dropped. (They are bodies set up after the
-- latest year the BUD covers, so no restated file can hold them.)
--   status: matched | in-year only | BUD only
--   same_prefix_in_bud: BUD codes with the same three-letter prefix but another number (a re-coded body)

DROP TABLE IF EXISTS audit.bud_inyear_org_match;
GO

WITH latest_release AS (
    SELECT TOP (1) release FROM stg.release ORDER BY release_seq DESC
), iy AS (
    SELECT r.organisation_code, MAX(r.organisation_name) AS organisation_name
    FROM raw.oscar_inyear AS r
    WHERE r.release = (SELECT release FROM latest_release)
    GROUP BY r.organisation_code
), iy_amount AS (
    SELECT s.organisation_code, COUNT_BIG(*) AS inyear_rows, SUM(s.amount) AS inyear_amount
    FROM stg.inyear_snapshot AS s
    WHERE s.release = (SELECT release FROM latest_release)
    GROUP BY s.organisation_code
), bud AS (
    SELECT organisation_code, MAX(organisation_name) AS organisation_name
    FROM stg.bud_organisation_type
    WHERE is_latest_vintage = 1
    GROUP BY organisation_code
), codes AS (
    SELECT organisation_code FROM iy UNION SELECT organisation_code FROM bud
)
SELECT
    CAST(c.organisation_code AS nvarchar(20)) AS organisation_code,
    CAST(COALESCE(i.organisation_name, b.organisation_name) AS nvarchar(200)) AS organisation_name,
    CAST((SELECT release FROM latest_release) AS varchar(7)) AS inyear_release,
    CAST(CASE WHEN i.organisation_code IS NOT NULL THEN 1 ELSE 0 END AS bit) AS in_inyear,
    CAST(CASE WHEN b.organisation_code IS NOT NULL THEN 1 ELSE 0 END AS bit) AS in_bud,
    CAST(CASE WHEN i.organisation_code IS NOT NULL AND b.organisation_code IS NOT NULL THEN 'matched'
              WHEN i.organisation_code IS NOT NULL THEN 'in-year only' ELSE 'BUD only' END AS varchar(14)) AS status,
    CAST(ISNULL(a.inyear_rows, 0) AS bigint) AS inyear_rows,
    CAST(ISNULL(a.inyear_amount, 0) AS decimal(19,4)) AS inyear_amount,
    CAST(ISNULL((SELECT STRING_AGG(o.organisation_code, ' ') WITHIN GROUP (ORDER BY o.organisation_code)
                 FROM bud AS o
                 WHERE LEFT(o.organisation_code, 3) = LEFT(c.organisation_code, 3)
                   AND o.organisation_code <> c.organisation_code), '') AS nvarchar(100)) AS same_prefix_in_bud
INTO audit.bud_inyear_org_match
FROM codes AS c
LEFT JOIN iy AS i ON i.organisation_code = c.organisation_code
LEFT JOIN bud AS b ON b.organisation_code = c.organisation_code
LEFT JOIN iy_amount AS a ON a.organisation_code = c.organisation_code;
GO

ALTER TABLE audit.bud_inyear_org_match ALTER COLUMN organisation_code nvarchar(20) NOT NULL;
GO
ALTER TABLE audit.bud_inyear_org_match ADD CONSTRAINT pk_audit_bud_inyear_org_match PRIMARY KEY (organisation_code);
GO
