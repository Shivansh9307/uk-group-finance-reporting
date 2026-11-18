-- audit.plan_phasing_summary: how the plans were phased, per plan year and profile method.
-- profiles = phasing profiles; plan_rows = dw.fact_plan rows that use them; negative_share_profiles = profiles
-- with at least one negative monthly share (a negative month in the prior year's outturn).
-- DERIVED counts, not amounts.

DROP TABLE IF EXISTS audit.plan_phasing_summary;
GO

CREATE TABLE audit.plan_phasing_summary (
    financial_year          varchar(7)   NOT NULL,
    method                  varchar(30)  NOT NULL,
    profiles                int          NOT NULL,
    plan_rows               int          NOT NULL,
    negative_share_profiles int          NOT NULL,
    CONSTRAINT pk_audit_plan_phasing_summary PRIMARY KEY (financial_year, method)
);
GO

WITH pr AS (
    SELECT profile_key, financial_year, method, MAX(CAST(has_negative_share AS int)) AS neg
    FROM dw.plan_phasing_profile
    GROUP BY profile_key, financial_year, method
), pf AS (
    SELECT profile_key, COUNT(DISTINCT plan_fact_key) AS plan_rows FROM dw.fact_plan_phased GROUP BY profile_key
)
INSERT INTO audit.plan_phasing_summary (financial_year, method, profiles, plan_rows, negative_share_profiles)
SELECT pr.financial_year, pr.method, COUNT(*), SUM(ISNULL(pf.plan_rows, 0)), SUM(pr.neg)
FROM pr
LEFT JOIN pf ON pf.profile_key = pr.profile_key
GROUP BY pr.financial_year, pr.method;
GO
