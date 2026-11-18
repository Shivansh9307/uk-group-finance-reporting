-- scope: full
-- audit.sr_group_bridge_vs_bud: the bridge's Spending Review group of every organisation code against the group the
-- newest annual release (BUD) gives that organisation.
--   Grain: organisation code x bridge group. The BUD group is the one of the newest financial year of the newest
--   vintage that lists the organisation (stg.bud_sr_group_by_organisation); its code is matched to dw.dim_sr_group, and
--   a name the current list lacks goes where authored/plan_name_map.csv puts it (as in dw.outturn_plan_basis_annual).
--   bridge_pairs     organisation version x sub-segment pairs of that organisation code that the bridge put in the group
--   status           agree          the bridge group is the BUD group
--                    differ         the bridge group is another group
--                    not_in_outturn the BUD lists the organisation but the in-year outturn has no pair for it
--                    not_in_bud     the bridge has the organisation but the newest BUD does not list it
-- Differences are expected where the bridge follows the current department of the line (a line that moved
-- department) and the BUD labels the organisation by where it sits in that annual file. Each one is read in
-- docs/data-dictionary/plan-phasing.md. Nothing here passes or fails by itself; sql/tests/561 pins the list.

DROP TABLE IF EXISTS audit.sr_group_bridge_vs_bud;
GO

CREATE TABLE audit.sr_group_bridge_vs_bud (
    organisation_code     nvarchar(50)   NOT NULL,
    bridge_group_code     varchar(20)    NOT NULL,
    bud_group_code        varchar(20)    NOT NULL,
    status                varchar(20)    NOT NULL,
    bridge_pairs          int            NOT NULL,
    bud_vintage           varchar(7)     NULL,
    bud_financial_year    varchar(7)     NULL,
    department_numbers    nvarchar(200)  NOT NULL,
    CONSTRAINT pk_audit_sr_group_bridge_vs_bud PRIMARY KEY (organisation_code, bridge_group_code, bud_group_code)
);
GO

WITH bud AS (
    SELECT x.organisation_code, x.vintage, x.financial_year,
           COALESCE(gc.sr_group_key, gn.sr_group_key) AS sr_group_key
    FROM (SELECT b.*, ROW_NUMBER() OVER (PARTITION BY b.organisation_code ORDER BY b.vintage DESC, b.financial_year DESC) AS rn
          FROM stg.bud_sr_group_by_organisation AS b
          WHERE b.vintage = (SELECT MAX(vintage) FROM stg.bud_sr_group_by_organisation)) AS x
    LEFT JOIN dw.dim_sr_group AS gc ON gc.sr_group_code = x.sr_group_code
    LEFT JOIN stg.plan_name_map AS m ON m.name_family = 'oscar_extract' AND m.plan_name = x.sr_group_name AND gc.sr_group_key IS NULL
    LEFT JOIN dw.dim_sr_group AS gn ON gn.sr_group_name = m.target_name
    WHERE x.rn = 1
), br AS (
    SELECT o.organisation_code, b.sr_group_key, COUNT(*) AS pairs
    FROM dw.outturn_sr_group_bridge AS b
    JOIN dw.dim_organisation AS o ON o.organisation_key = b.organisation_key
    GROUP BY o.organisation_code, b.sr_group_key
), br2 AS (
    SELECT br.organisation_code, br.sr_group_key, br.pairs,
           (SELECT STRING_AGG(y.department_number, ' ') WITHIN GROUP (ORDER BY y.department_number)
            FROM (SELECT DISTINCT b3.department_number
                  FROM dw.outturn_sr_group_bridge AS b3 JOIN dw.dim_organisation AS o3 ON o3.organisation_key = b3.organisation_key
                  WHERE o3.organisation_code = br.organisation_code AND b3.sr_group_key = br.sr_group_key) AS y) AS departments
    FROM br
)
INSERT INTO audit.sr_group_bridge_vs_bud
    (organisation_code, bridge_group_code, bud_group_code, status, bridge_pairs, bud_vintage, bud_financial_year, department_numbers)
SELECT COALESCE(br2.organisation_code, bud.organisation_code),
       ISNULL(bg.sr_group_code, 'none'), ISNULL(ug.sr_group_code, 'none'),
       CASE WHEN br2.organisation_code IS NULL THEN 'not_in_outturn'
            WHEN bud.organisation_code IS NULL THEN 'not_in_bud'
            WHEN br2.sr_group_key = bud.sr_group_key THEN 'agree' ELSE 'differ' END,
       ISNULL(br2.pairs, 0), bud.vintage, bud.financial_year, ISNULL(br2.departments, '')
FROM br2
FULL OUTER JOIN bud ON bud.organisation_code = br2.organisation_code
LEFT JOIN dw.dim_sr_group AS bg ON bg.sr_group_key = br2.sr_group_key
LEFT JOIN dw.dim_sr_group AS ug ON ug.sr_group_key = bud.sr_group_key;
GO
