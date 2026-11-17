-- scope: full
-- audit.bud_vs_inyear_del: the in-year year-end release against each BUD vintage that holds the year.
--   The year-end release is the June release of the following year (periods 1 to 12 of the financial year,
--   stg.release.highest_period = 12). For each financial year and each annual vintage that holds it, the
--   in-year amount is the sum of stg.inyear_snapshot for that release and the BUD amount is the sum of
--   dw.fact_outturn_annual (every TYPE layer, Closed rows excluded). Amounts are GBP thousands.
--   gap = in-year minus BUD; gap_share_of_bud = gap / BUD.
--   level DEL: the control. status is pass when the gap is within 3.5% of the BUD amount, else fail.
--   levels AME, NON-BUDGET, TOTAL: recorded, status 'boundary difference' and never a failure. The restated
--   files hold layers the in-year files do not (non-budget), and provisions, impairments and pension
--   adjustments that are loaded after the June in-year snapshot (AME).
--   is_latest_vintage_for_year = no later vintage holds that year.
--   Basis note for DEL: the in-year file is summed as published, the BUD file with every TYPE layer; the
--   June snapshot is not the final outturn, so part of the gap is movement after June.

DROP TABLE IF EXISTS audit.bud_vs_inyear_del;
GO

WITH yearend AS (
    SELECT financial_year, release FROM stg.release WHERE highest_period = 12
), iy AS (
    SELECT y.financial_year, y.release,
           CASE s.control_budget_code
                WHEN 'DEL' THEN 'DEL' WHEN 'TOTAL DEL' THEN 'DEL'
                WHEN 'AME' THEN 'AME' WHEN 'TOTAL AME' THEN 'AME'
                WHEN 'NON-BUDGET' THEN 'NON-BUDGET' WHEN 'TOTAL NON-BUDGET' THEN 'NON-BUDGET'
                ELSE 'OTHER' END AS level,
           SUM(s.amount) AS amount
    FROM yearend AS y
    JOIN stg.inyear_snapshot AS s ON s.release = y.release AND s.financial_year = y.financial_year
    GROUP BY y.financial_year, y.release,
             CASE s.control_budget_code
                  WHEN 'DEL' THEN 'DEL' WHEN 'TOTAL DEL' THEN 'DEL'
                  WHEN 'AME' THEN 'AME' WHEN 'TOTAL AME' THEN 'AME'
                  WHEN 'NON-BUDGET' THEN 'NON-BUDGET' WHEN 'TOTAL NON-BUDGET' THEN 'NON-BUDGET'
                  ELSE 'OTHER' END
), iy_all AS (
    SELECT financial_year, release, level, amount FROM iy
    UNION ALL
    SELECT financial_year, release, 'TOTAL', SUM(amount) FROM iy GROUP BY financial_year, release
), bud AS (
    SELECT vintage, financial_year,
           CASE control_budget_code WHEN 'DEL' THEN 'DEL' WHEN 'AME' THEN 'AME' WHEN 'NON-BUDGET' THEN 'NON-BUDGET'
                ELSE 'OTHER' END AS level,
           SUM(amount) AS amount
    FROM dw.fact_outturn_annual
    GROUP BY vintage, financial_year,
             CASE control_budget_code WHEN 'DEL' THEN 'DEL' WHEN 'AME' THEN 'AME' WHEN 'NON-BUDGET' THEN 'NON-BUDGET'
                  ELSE 'OTHER' END
), bud_all AS (
    SELECT vintage, financial_year, level, amount FROM bud
    UNION ALL
    SELECT vintage, financial_year, 'TOTAL', SUM(amount) FROM bud GROUP BY vintage, financial_year
), pairs AS (
    SELECT b.financial_year, b.vintage, b.level, i.release AS inyear_release,
           i.amount AS inyear_amount, b.amount AS bud_amount
    FROM bud_all AS b
    JOIN iy_all AS i ON i.financial_year = b.financial_year AND i.level = b.level
    WHERE b.level IN ('DEL', 'AME', 'NON-BUDGET', 'TOTAL')
)
SELECT
    CAST(p.financial_year AS varchar(7)) AS financial_year,
    CAST(p.vintage AS varchar(7)) AS vintage,
    CAST(p.level AS varchar(12)) AS level,
    CAST(p.inyear_release AS varchar(7)) AS inyear_release,
    CAST(p.inyear_amount AS decimal(19,4)) AS inyear_amount,
    CAST(p.bud_amount AS decimal(19,4)) AS bud_amount,
    CAST(p.inyear_amount - p.bud_amount AS decimal(19,4)) AS gap,
    CAST((p.inyear_amount - p.bud_amount) / NULLIF(p.bud_amount, 0) AS decimal(12,6)) AS gap_share_of_bud,
    CAST(CASE WHEN p.level = 'DEL' THEN 0.035 END AS decimal(6,4)) AS tolerance_share,
    CAST(CASE WHEN p.level <> 'DEL' THEN 'boundary difference'
              WHEN ABS((p.inyear_amount - p.bud_amount) / NULLIF(p.bud_amount, 0)) <= 0.035 THEN 'pass'
              ELSE 'fail' END AS varchar(20)) AS status,
    CAST(CASE WHEN NOT EXISTS (SELECT 1 FROM raw.oscar_bud_file AS later
                               WHERE later.file_kind = 'data' AND later.financial_year = p.financial_year
                                 AND later.vintage > p.vintage) THEN 1 ELSE 0 END AS bit) AS is_latest_vintage_for_year,
    CAST(CASE p.level
         WHEN 'DEL' THEN 'control: DEL at total level; the June in-year snapshot is not final outturn'
         WHEN 'AME' THEN 'AME moves after June (provisions, impairments, pension adjustments are loaded later)'
         WHEN 'NON-BUDGET' THEN 'restated files carry non-budget layers that the in-year files do not'
         ELSE 'sum of the control budget levels; inherits the AME and non-budget differences' END AS varchar(120)) AS basis_note
INTO audit.bud_vs_inyear_del
FROM pairs AS p;
GO

ALTER TABLE audit.bud_vs_inyear_del ALTER COLUMN financial_year varchar(7) NOT NULL;
GO
ALTER TABLE audit.bud_vs_inyear_del ALTER COLUMN vintage varchar(7) NOT NULL;
GO
ALTER TABLE audit.bud_vs_inyear_del ALTER COLUMN level varchar(12) NOT NULL;
GO
ALTER TABLE audit.bud_vs_inyear_del ADD CONSTRAINT pk_audit_bud_vs_inyear_del PRIMARY KEY (financial_year, vintage, level);
GO
