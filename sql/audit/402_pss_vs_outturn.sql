-- scope: full
-- audit.pss_vs_outturn: the Public Spending Statistics database against OSCAR outturn, by financial year,
-- Spending Review group and measure. GBP thousands; gap = PSS minus OSCAR.
--   Measures: RDEL_EX_DEPN = resource DEL excluding depreciation; CDEL = capital DEL.
--   Two comparisons for every year they share with the PSS (2021-22 to 2025-26):
--     BUD      dw.fact_outturn_annual from the latest annual vintage that holds the year (2021-22 to 2024-25).
--              Resource DEL excluding depreciation is control budget DEL, economic budget RESOURCE, ringfence
--              <> 'RINGFENCED': the exact basis.
--     IN-YEAR  the June in-year release of the following year (2021-22 to 2025-26). The in-year files have no
--              ringfence column, so resource excluding depreciation drops the PESA economic group
--              DEPRECIATION, which leaves impairments and other non-cash items in (about 5.5bn from
--              2024-25). Rows are given a group through the organisation's group in the newest BUD
--              vintage (its latest year there): one rule for every year, on the current structure.
--   Levels:
--     SR GROUP              one row per group, status 'recorded'. Money moves between groups in the PSS and
--                           OSCAR (2023-24: Education/Work and Pensions 4.1bn), so no group-level tolerance.
--     TOTAL                 all groups. For resource DEL the Scotland gap (block grant adjustment, which the
--                           PSS takes off and OSCAR does not) is inside it: status 'recorded'.
--     TOTAL EXCL SCOTLAND   every group except Scotland: the control row, graded.
--   Tolerance on the control row: 0.1% from 2023-24, 1% before. status: pass when |gap| / OSCAR is under it;
--   otherwise fail for BUD, and 'basis difference' for IN-YEAR (the in-year basis above is the stated reason).
--   The PSS leaves out the security and intelligence agencies and the operational costs of military
--   operations; departmental AME is not compared (it does not reconcile: see the profiling notes).

DROP TABLE IF EXISTS audit.pss_vs_outturn;
GO

WITH pss AS (
    SELECT p.financial_year, ISNULL(m.sr_group_name, N'UNMATCHED') AS sr_group_name,
           CASE WHEN p.basis_rdel_excl_depreciation = 1 THEN 'RDEL_EX_DEPN' ELSE 'CDEL' END AS measure,
           SUM(p.amount) AS amount
    FROM stg.pss_outturn AS p
    LEFT JOIN stg.pss_sr_group_map AS m ON m.pss_sr_group_name = p.sr_group_name
    WHERE p.basis_rdel_excl_depreciation = 1 OR (p.control_budget_code = 'DEL' AND p.economic_budget_code = 'CAPITAL')
    GROUP BY p.financial_year, ISNULL(m.sr_group_name, N'UNMATCHED'),
             CASE WHEN p.basis_rdel_excl_depreciation = 1 THEN 'RDEL_EX_DEPN' ELSE 'CDEL' END
), latest_vintage AS (
    SELECT financial_year, MAX(vintage) AS vintage FROM raw.oscar_bud_file WHERE file_kind = 'data' GROUP BY financial_year
), bud AS (
    SELECT 'BUD' AS comparison, f.financial_year, f.vintage AS source_release,
           ISNULL(m.sr_group_name, N'UNMATCHED') AS sr_group_name,
           CASE WHEN f.basis_rdel_excl_depreciation = 1 THEN 'RDEL_EX_DEPN' ELSE 'CDEL' END AS measure,
           SUM(f.amount) AS amount
    FROM dw.fact_outturn_annual AS f
    JOIN latest_vintage AS lv ON lv.financial_year = f.financial_year AND lv.vintage = f.vintage
    LEFT JOIN stg.bud_sr_group_by_organisation AS m
           ON m.vintage = f.vintage AND m.financial_year = f.financial_year AND m.organisation_code = f.organisation_code
    WHERE f.basis_rdel_excl_depreciation = 1 OR (f.control_budget_code = 'DEL' AND f.economic_budget_code = 'CAPITAL')
    GROUP BY f.financial_year, f.vintage, ISNULL(m.sr_group_name, N'UNMATCHED'),
             CASE WHEN f.basis_rdel_excl_depreciation = 1 THEN 'RDEL_EX_DEPN' ELSE 'CDEL' END
), org_current AS (
    SELECT organisation_code, sr_group_name
    FROM (SELECT organisation_code, sr_group_name,
                 ROW_NUMBER() OVER (PARTITION BY organisation_code ORDER BY financial_year DESC) AS rn
          FROM stg.bud_sr_group_by_organisation WHERE is_latest_vintage = 1) AS x
    WHERE rn = 1
), inyear AS (
    SELECT 'IN-YEAR' AS comparison, s.financial_year, r.release AS source_release,
           ISNULL(o.sr_group_name, N'UNMATCHED') AS sr_group_name,
           CASE WHEN s.economic_budget_code = 'CAPITAL' THEN 'CDEL' ELSE 'RDEL_EX_DEPN' END AS measure,
           SUM(s.amount) AS amount
    FROM stg.release AS r
    JOIN stg.inyear_snapshot AS s ON s.release = r.release AND s.financial_year = r.financial_year
    LEFT JOIN org_current AS o ON o.organisation_code = s.organisation_code
    WHERE r.highest_period = 12
      AND s.control_budget_code IN ('DEL', 'TOTAL DEL')
      AND ((s.economic_budget_code = 'CAPITAL')
        OR (s.economic_budget_code = 'RESOURCE' AND s.pesa_economic_group_code <> 'DEPRECIATION'))
    GROUP BY s.financial_year, r.release, ISNULL(o.sr_group_name, N'UNMATCHED'),
             CASE WHEN s.economic_budget_code = 'CAPITAL' THEN 'CDEL' ELSE 'RDEL_EX_DEPN' END
), other_side AS (
    SELECT * FROM bud UNION ALL SELECT * FROM inyear
), cmp AS (
    SELECT DISTINCT comparison, financial_year, source_release FROM other_side
), pss_x AS (
    SELECT c.comparison, c.financial_year, c.source_release, p.sr_group_name, p.measure, p.amount
    FROM cmp AS c
    JOIN pss AS p ON p.financial_year = c.financial_year
), grp AS (
    SELECT COALESCE(x.comparison, o.comparison) AS comparison,
           COALESCE(x.financial_year, o.financial_year) AS financial_year,
           COALESCE(x.source_release, o.source_release) AS source_release,
           COALESCE(x.sr_group_name, o.sr_group_name) AS sr_group_name,
           COALESCE(x.measure, o.measure) AS measure,
           x.amount AS pss_amount, o.amount AS oscar_amount
    FROM pss_x AS x
    FULL OUTER JOIN other_side AS o
         ON o.comparison = x.comparison AND o.financial_year = x.financial_year
        AND o.sr_group_name = x.sr_group_name AND o.measure = x.measure
    WHERE COALESCE(x.financial_year, o.financial_year) IN (SELECT financial_year FROM pss)
), levels AS (
    SELECT comparison, financial_year, source_release, 'SR GROUP' AS level, sr_group_name, measure,
           ISNULL(pss_amount, 0) AS pss_amount, ISNULL(oscar_amount, 0) AS oscar_amount
    FROM grp
    UNION ALL
    SELECT comparison, financial_year, source_release, 'TOTAL', N'ALL', measure,
           SUM(ISNULL(pss_amount, 0)), SUM(ISNULL(oscar_amount, 0))
    FROM grp GROUP BY comparison, financial_year, source_release, measure
    UNION ALL
    SELECT comparison, financial_year, source_release, 'TOTAL EXCL SCOTLAND', N'ALL EXCEPT Scotland', measure,
           SUM(ISNULL(pss_amount, 0)), SUM(ISNULL(oscar_amount, 0))
    FROM grp WHERE sr_group_name <> N'Scotland' GROUP BY comparison, financial_year, source_release, measure
)
SELECT
    CAST(l.comparison AS varchar(8)) AS comparison,
    CAST(l.financial_year AS varchar(7)) AS financial_year,
    CAST(l.source_release AS varchar(7)) AS source_release,
    CAST(l.level AS varchar(20)) AS level,
    CAST(l.sr_group_name AS nvarchar(100)) AS sr_group_name,
    CAST(l.measure AS varchar(12)) AS measure,
    CAST(l.pss_amount AS decimal(19,4)) AS pss_amount,
    CAST(l.oscar_amount AS decimal(19,4)) AS oscar_amount,
    CAST(l.pss_amount - l.oscar_amount AS decimal(19,4)) AS gap,
    CAST((l.pss_amount - l.oscar_amount) / NULLIF(l.oscar_amount, 0) AS decimal(12,6)) AS gap_share_of_oscar,
    CAST(CASE WHEN l.level = 'TOTAL EXCL SCOTLAND'
              THEN CASE WHEN l.financial_year >= '2023-24' THEN 0.001 ELSE 0.01 END END AS decimal(6,4)) AS tolerance_share,
    CAST(CASE WHEN l.level <> 'TOTAL EXCL SCOTLAND' THEN 'recorded'
              WHEN ABS((l.pss_amount - l.oscar_amount) / NULLIF(l.oscar_amount, 0))
                   < CASE WHEN l.financial_year >= '2023-24' THEN 0.001 ELSE 0.01 END THEN 'pass'
              WHEN l.comparison = 'BUD' THEN 'fail'
              ELSE 'basis difference' END AS varchar(20)) AS status,
    CAST(CASE WHEN l.comparison = 'BUD'
              THEN 'OSCAR side: BUD DEL, exact basis (ringfence column), latest vintage holding the year'
              ELSE 'OSCAR side: in-year June release, no ringfence column, PESA group DEPRECIATION dropped' END AS varchar(120)) AS basis_note
INTO audit.pss_vs_outturn
FROM levels AS l;
GO

ALTER TABLE audit.pss_vs_outturn ALTER COLUMN comparison varchar(8) NOT NULL;
GO
ALTER TABLE audit.pss_vs_outturn ALTER COLUMN financial_year varchar(7) NOT NULL;
GO
ALTER TABLE audit.pss_vs_outturn ALTER COLUMN level varchar(20) NOT NULL;
GO
ALTER TABLE audit.pss_vs_outturn ALTER COLUMN sr_group_name nvarchar(100) NOT NULL;
GO
ALTER TABLE audit.pss_vs_outturn ALTER COLUMN measure varchar(12) NOT NULL;
GO
ALTER TABLE audit.pss_vs_outturn ADD CONSTRAINT pk_audit_pss_vs_outturn
    PRIMARY KEY (comparison, financial_year, level, sr_group_name, measure);
GO
