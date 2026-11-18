-- scope: full
-- audit.current_structure_holdout: the in-year outturn on the current structure against the restated annual
-- file that was not used to build or review the map (vintage 2025-11).
--   One row per financial year the vintage covers, level (DEL, TOTAL) and current department.
--   inyear_amount   the year-end in-year release of that financial year (the June release that holds periods
--                   1 to 12), every line sent to its current department by stg.current_structure_map.
--                   DEL = control_budget_code DEL or TOTAL DEL, as in audit.bud_vs_inyear_del
--   bud_amount      dw.fact_outturn_annual of the 2025-11 vintage (every TYPE layer, Closed rows excluded), each
--                   organisation sent to the department of its department group for that year
--                   (stg.bud_sr_group_by_organisation, dw.bud_group_current_department)
--   residual        inyear_amount - bud_amount; residual_share_of_bud = residual / bud_amount (NULL when the BUD
--                   amount is 0)
--   current_department_key = -1 holds the BUD groups that have no department in the in-year series
--   (department_number NONE). Nothing here is a pass or a fail: before 2024-25 the annual files are not a
--   department-level control (DEL is within -3.2% to +3.4% only in total, audit.bud_vs_inyear_del), so the
--   residual is published and read in docs/data-dictionary/current-structure.md.
--   Amounts are GBP thousands, spending positive.

DROP TABLE IF EXISTS audit.current_structure_holdout;
GO

CREATE TABLE audit.current_structure_holdout (
    financial_year           varchar(7)    NOT NULL,
    level                    varchar(10)   NOT NULL,
    current_department_key   int           NOT NULL,
    department_number        nvarchar(10)  NOT NULL,
    department_name          nvarchar(400) NOT NULL,
    member_type              varchar(20)   NOT NULL,
    inyear_release           varchar(7)    NOT NULL,
    inyear_amount            decimal(19,4) NOT NULL,
    bud_amount               decimal(19,4) NOT NULL,
    residual                 decimal(19,4) NOT NULL,
    residual_share_of_bud    decimal(19,6) NULL,
    CONSTRAINT pk_audit_current_structure_holdout PRIMARY KEY (financial_year, level, current_department_key)
);
GO

WITH vintage AS (
    SELECT N'2025-11' AS vintage
), years AS (
    SELECT DISTINCT b.financial_year FROM dw.fact_outturn_annual AS b JOIN vintage AS v ON v.vintage = b.vintage
), yearend AS (
    SELECT r.financial_year, r.release FROM stg.release AS r WHERE r.highest_period = 12
), iy AS (
    SELECT y.financial_year, y.release, c.current_department_key,
           CASE WHEN s.control_budget_code IN (N'DEL', N'TOTAL DEL') THEN 1 ELSE 0 END AS is_del,
           SUM(s.amount) AS amount
    FROM yearend AS y
    JOIN years AS ys ON ys.financial_year = y.financial_year
    JOIN stg.inyear_snapshot AS s ON s.release = y.release AND s.financial_year = y.financial_year
    JOIN dw.organisation_release_map AS m ON m.release = s.release AND m.organisation_code = s.organisation_code
    JOIN stg.current_structure_map AS c ON c.organisation_key = m.organisation_key AND c.sub_segment_code = s.sub_segment_code
    GROUP BY y.financial_year, y.release, c.current_department_key,
             CASE WHEN s.control_budget_code IN (N'DEL', N'TOTAL DEL') THEN 1 ELSE 0 END
), iy_level AS (
    SELECT financial_year, release, current_department_key, N'TOTAL' AS level, SUM(amount) AS amount
    FROM iy GROUP BY financial_year, release, current_department_key
    UNION ALL
    SELECT financial_year, release, current_department_key, N'DEL', SUM(amount) FROM iy WHERE is_del = 1
    GROUP BY financial_year, release, current_department_key
), bud AS (
    SELECT f.financial_year, ISNULL(g.current_department_key, -1) AS current_department_key,
           CASE WHEN f.control_budget_code = N'DEL' THEN 1 ELSE 0 END AS is_del, SUM(f.amount) AS amount
    FROM dw.fact_outturn_annual AS f
    JOIN vintage AS v ON v.vintage = f.vintage
    LEFT JOIN stg.bud_sr_group_by_organisation AS o
           ON o.vintage = f.vintage AND o.financial_year = f.financial_year AND o.organisation_code = f.organisation_code
    LEFT JOIN dw.bud_group_current_department AS g ON g.department_group_code = o.department_group_code
    GROUP BY f.financial_year, ISNULL(g.current_department_key, -1), CASE WHEN f.control_budget_code = N'DEL' THEN 1 ELSE 0 END
), bud_level AS (
    SELECT financial_year, current_department_key, N'TOTAL' AS level, SUM(amount) AS amount
    FROM bud GROUP BY financial_year, current_department_key
    UNION ALL
    SELECT financial_year, current_department_key, N'DEL', SUM(amount) FROM bud WHERE is_del = 1
    GROUP BY financial_year, current_department_key
), both_sides AS (
    SELECT COALESCE(i.financial_year, b.financial_year) AS financial_year, COALESCE(i.level, b.level) AS level,
           COALESCE(i.current_department_key, b.current_department_key) AS current_department_key,
           i.release, ISNULL(i.amount, 0) AS inyear_amount, ISNULL(b.amount, 0) AS bud_amount
    FROM iy_level AS i
    FULL OUTER JOIN bud_level AS b
      ON b.financial_year = i.financial_year AND b.level = i.level AND b.current_department_key = i.current_department_key
)
INSERT INTO audit.current_structure_holdout
SELECT s.financial_year, s.level, s.current_department_key,
       CASE WHEN s.current_department_key = -1 THEN N'NONE' ELSE d.department_number END,
       CASE WHEN s.current_department_key = -1 THEN N'BUD group with no department in the in-year series' ELSE d.department_name END,
       CASE WHEN s.current_department_key = -1 THEN 'None' ELSE d.member_type END,
       ISNULL(s.release, ye.release),
       CAST(s.inyear_amount AS decimal(19,4)), CAST(s.bud_amount AS decimal(19,4)),
       CAST(s.inyear_amount - s.bud_amount AS decimal(19,4)),
       CASE WHEN s.bud_amount = 0 THEN NULL ELSE CAST((s.inyear_amount - s.bud_amount) / s.bud_amount AS decimal(19,6)) END
FROM both_sides AS s
LEFT JOIN dw.dim_department AS d ON d.department_key = s.current_department_key
LEFT JOIN yearend AS ye ON ye.financial_year = s.financial_year
WHERE s.inyear_amount <> 0 OR s.bud_amount <> 0;
GO
