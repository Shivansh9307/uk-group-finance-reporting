-- scope: full
-- audit.plan_basis_inyear_vs_annual: the in-year outturn on the plan's measures at the year-end release against the
-- annual restated outturn (BUD) on the exact basis, per financial year x Spending Review group x measure.
--   inyear_amount   dw.outturn_plan_basis_inyear at the release that closes the year, summed over periods 0 to 12;
--                   groups through the bridge (current structure)
--   annual_amount   dw.outturn_plan_basis_annual from the newest vintage that holds the year; groups are the BUD's own
--   gap             inyear_amount - annual_amount; gap_pct is gap over annual_amount in percent
-- Gaps are expected: the in-year June release is the first look at the year and the annual file is restated,
-- the in-year files have no ringfence column (RDEL_EX_DEPN leaves other non-cash items in), and the bridge and the
-- BUD can disagree on a group (see audit.sr_group_bridge_vs_bud). Nothing here passes or fails.

DROP TABLE IF EXISTS audit.plan_basis_inyear_vs_annual;
GO

CREATE TABLE audit.plan_basis_inyear_vs_annual (
    financial_year  varchar(7)     NOT NULL,
    sr_group_code   varchar(20)    NOT NULL,
    measure         varchar(40)    NOT NULL,
    inyear_release  varchar(7)     NULL,
    inyear_amount   decimal(19,4)  NULL,
    annual_vintage  varchar(7)     NULL,
    annual_amount   decimal(19,4)  NULL,
    gap             decimal(19,4)  NULL,
    gap_pct         decimal(19,4)  NULL,
    CONSTRAINT pk_audit_plan_basis_inyear_vs_annual PRIMARY KEY (financial_year, sr_group_code, measure)
);
GO

WITH i AS (
    SELECT b.financial_year, b.sr_group_key, b.measure, MAX(r.label) AS release_label, SUM(b.amount) AS amount
    FROM dw.outturn_plan_basis_inyear AS b
    JOIN dw.dim_release AS r ON r.release_key = b.release_key
    WHERE b.is_year_end_release = 1 AND b.measure IN ('RDEL', 'RDEL_EX_DEPN', 'CDEL')
    GROUP BY b.financial_year, b.sr_group_key, b.measure
), a AS (
    SELECT financial_year, sr_group_key, measure, MAX(vintage) AS vintage, SUM(amount) AS amount
    FROM dw.outturn_plan_basis_annual
    WHERE is_latest_vintage_for_year = 1
    GROUP BY financial_year, sr_group_key, measure
)
INSERT INTO audit.plan_basis_inyear_vs_annual
    (financial_year, sr_group_code, measure, inyear_release, inyear_amount, annual_vintage, annual_amount, gap, gap_pct)
SELECT COALESCE(i.financial_year, a.financial_year), g.sr_group_code, COALESCE(i.measure, a.measure),
       i.release_label, i.amount, a.vintage, a.amount,
       CAST(ISNULL(i.amount, 0) - ISNULL(a.amount, 0) AS decimal(19, 4)),
       CASE WHEN a.amount IS NULL OR a.amount = 0 THEN NULL
            ELSE CAST(100 * (ISNULL(i.amount, 0) - a.amount) / a.amount AS decimal(19, 4)) END
FROM i
FULL OUTER JOIN a ON a.financial_year = i.financial_year AND a.sr_group_key = i.sr_group_key AND a.measure = i.measure
JOIN dw.dim_sr_group AS g ON g.sr_group_key = COALESCE(i.sr_group_key, a.sr_group_key);
GO
