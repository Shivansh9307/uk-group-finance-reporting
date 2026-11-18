-- dw.plan_phasing_profile: how each annual plan is spread over the twelve months. DERIVED, not published.
--
-- For a plan in financial year Y the monthly shares come from the outturn of year Y-1, as at the release that
-- closes Y-1 (dim_release.is_year_end_release): the sum of the revision deltas with release_key up to that release.
-- Period 0 (the 71 June 2019 rows not allocated to a month) is left out and the shares are renormalised over
-- periods 1 to 12. One profile is a set of twelve rows, one per period, and covers every plan row of its key:
--   profile_basis 'organisation'  plan grain A (OSCAR Plans): financial year x organisation x control budget
--                                 detail x economic budget, taken from the outturn lines of that organisation code
--   profile_basis 'group'         plan grains B, C and D: financial year x Spending Review group x measure; the
--                                 outturn lines come from dw.plan_measure_selection and the bridge group. The
--                                 combined pre-2023 group is the lines of the departments that
--                                 stg.department_sr_group (basis pre2023_as_reported) lists, as the release
--                                 reported them
-- method:
--   prior_year_outturn      the share of a month is its outturn over the year's total, rounded to ten places
--   flat_no_prior_year      no year-end release for Y-1 exists (the first plan years, and the years beyond the
--                           outturn), or the profile has no outturn line in Y-1: twelve flat twelfths
--   flat_prior_not_positive Y-1 has outturn but its total is zero or negative: twelve flat twelfths
-- The rounding remainder goes to period 12, so the twelve shares add up to exactly 1. A share can be negative or
-- above 1 when a month of the prior year was negative; has_negative_share says so.
-- Plan years before FY2018-19 have no calendar and no monthly outturn (the in-year releases start with FY2018-19)
-- and are not phased.
--   prior_period_amount / prior_year_total   the outturn the shares come from, GBP thousands (NULL when there is none)
-- is_derived = 1 on every row: the table is derived and never reaches a real total.

DROP TABLE IF EXISTS dw.fact_plan_phased;
DROP TABLE IF EXISTS dw.plan_phasing_profile;
GO

DROP TABLE IF EXISTS #pk;
DROP TABLE IF EXISTS #ye;
DROP TABLE IF EXISTS #m;
DROP TABLE IF EXISTS #t;
GO

SELECT CAST(ROW_NUMBER() OVER (ORDER BY x.profile_basis, x.financial_year, x.sr_group_key, x.organisation_code,
                                         x.control_budget_detail, x.economic_budget, x.measure) AS int) AS profile_key,
       x.profile_basis, x.financial_year,
       CAST(CAST(LEFT(x.financial_year, 4) AS int) - 1 AS varchar(4)) + '-' + RIGHT(LEFT(x.financial_year, 4), 2) AS prior_financial_year,
       x.sr_group_key, x.organisation_code, x.control_budget_detail, x.economic_budget, x.measure
INTO #pk
FROM (
    SELECT DISTINCT
           CAST(CASE WHEN p.grain_code = 'A' THEN 'organisation' ELSE 'group' END AS varchar(12)) AS profile_basis,
           p.financial_year, p.sr_group_key,
           CASE WHEN p.grain_code = 'A' THEN p.organisation_code END AS organisation_code,
           CASE WHEN p.grain_code = 'A' THEN p.control_budget_detail END AS control_budget_detail,
           CASE WHEN p.grain_code = 'A' THEN p.economic_budget END AS economic_budget,
           p.measure
    FROM dw.fact_plan AS p
    WHERE EXISTS (SELECT 1 FROM dw.dim_period AS d WHERE d.financial_year = p.financial_year)
) AS x;
GO

-- the release that closes each financial year (none for a year that is not finished)
SELECT k.profile_key, ye.release_key AS year_end_release_key
INTO #ye
FROM #pk AS k
JOIN dw.dim_release AS ye ON ye.financial_year = k.prior_financial_year AND ye.is_year_end_release = 1;
GO

SELECT profile_key, period_no, SUM(amount) AS amount
INTO #m
FROM (
    -- organisation basis: the lines of that organisation code, control budget detail and economic budget
    SELECT k.profile_key, l.period_no, l.amount_delta AS amount
    FROM #pk AS k
    JOIN #ye AS ye ON ye.profile_key = k.profile_key
    JOIN dw.outturn_plan_line AS l
      ON l.financial_year = k.prior_financial_year AND l.release_key <= ye.year_end_release_key
     AND l.organisation_code = k.organisation_code AND l.control_budget_detail = k.control_budget_detail
     AND l.economic_budget = k.economic_budget
    WHERE k.profile_basis = 'organisation' AND l.period_no BETWEEN 1 AND 12
    UNION ALL
    -- group basis, a Spending Review group of the current structure
    SELECT k.profile_key, l.period_no, l.amount_delta
    FROM #pk AS k
    JOIN #ye AS ye ON ye.profile_key = k.profile_key
    JOIN dw.dim_sr_group AS g ON g.sr_group_key = k.sr_group_key AND g.member_type <> 'combined_pre_2023'
    JOIN dw.plan_measure_selection AS ms ON ms.measure = k.measure
    JOIN dw.outturn_plan_line AS l
      ON l.financial_year = k.prior_financial_year AND l.release_key <= ye.year_end_release_key
     AND l.sr_group_key = k.sr_group_key AND l.control_budget_detail = ms.control_budget_detail
     AND l.economic_budget = ms.economic_budget AND (ms.excludes_depreciation = 0 OR l.is_depreciation = 0)
    WHERE k.profile_basis = 'group' AND l.period_no BETWEEN 1 AND 12
    UNION ALL
    -- group basis, the combined pre-2023 group: departments as the release reported them
    SELECT k.profile_key, l.period_no, l.amount_delta
    FROM #pk AS k
    JOIN #ye AS ye ON ye.profile_key = k.profile_key
    JOIN dw.dim_sr_group AS g ON g.sr_group_key = k.sr_group_key AND g.member_type = 'combined_pre_2023'
    JOIN dw.plan_measure_selection AS ms ON ms.measure = k.measure
    JOIN dw.outturn_plan_line AS l
      ON l.financial_year = k.prior_financial_year AND l.release_key <= ye.year_end_release_key
     AND l.control_budget_detail = ms.control_budget_detail
     AND l.economic_budget = ms.economic_budget AND (ms.excludes_depreciation = 0 OR l.is_depreciation = 0)
    WHERE k.profile_basis = 'group' AND l.period_no BETWEEN 1 AND 12
      AND l.reported_department_number IN (SELECT department_number FROM stg.department_sr_group WHERE basis = 'pre2023_as_reported')
) AS u
GROUP BY profile_key, period_no;
GO

SELECT k.profile_key,
       CAST(SUM(m.amount) AS decimal(19,4)) AS prior_year_total,
       CAST(CASE WHEN COUNT(m.profile_key) = 0 THEN 'flat_no_prior_year'
                 WHEN SUM(m.amount) > 0 THEN 'prior_year_outturn'
                 ELSE 'flat_prior_not_positive' END AS varchar(30)) AS method
INTO #t
FROM #pk AS k
LEFT JOIN #m AS m ON m.profile_key = k.profile_key
GROUP BY k.profile_key;
GO

-- no year-end release for the prior year: flat, whatever the lines say (there are none)
UPDATE t SET method = 'flat_no_prior_year'
FROM #t AS t
WHERE NOT EXISTS (SELECT 1 FROM #ye AS ye WHERE ye.profile_key = t.profile_key);
GO

CREATE TABLE dw.plan_phasing_profile (
    profile_key          int            NOT NULL,
    profile_basis        varchar(12)    NOT NULL,   -- organisation | group
    financial_year       varchar(7)     NOT NULL,   -- the plan year
    prior_financial_year varchar(7)     NOT NULL,
    year_end_release_key int            NULL,       -- the release that closes the prior year; NULL when there is none
    sr_group_key         int            NOT NULL,
    organisation_code    nvarchar(50)   NULL,       -- organisation basis only
    control_budget_detail varchar(30)   NULL,       -- organisation basis only
    economic_budget      varchar(20)    NULL,       -- organisation basis only
    measure              varchar(40)    NOT NULL,
    period_no            tinyint        NOT NULL,   -- 1 to 12
    period_key           int            NOT NULL,   -- the plan year's period
    share                decimal(19,10) NOT NULL,
    method               varchar(30)    NOT NULL,
    prior_period_amount  decimal(19,4)  NULL,
    prior_year_total     decimal(19,4)  NULL,
    has_negative_share   bit            NOT NULL,
    is_derived           bit            NOT NULL,
    CONSTRAINT pk_dw_plan_phasing_profile PRIMARY KEY (profile_key, period_no)
);
GO

WITH s AS (
    SELECT k.profile_key, k.profile_basis, k.financial_year, k.prior_financial_year, ye.year_end_release_key, k.sr_group_key,
           k.organisation_code, k.control_budget_detail, k.economic_budget, k.measure,
           n.period_no, CAST(LEFT(k.financial_year, 4) AS int) * 100 + n.period_no AS period_key,
           t.method, t.prior_year_total, m.amount AS prior_period_amount,
           CAST(CASE WHEN t.method = 'prior_year_outturn'
                     THEN ROUND(CAST(ISNULL(m.amount, 0) AS decimal(28, 10)) / CAST(t.prior_year_total AS decimal(28, 10)), 10)
                     ELSE ROUND(CAST(1 AS decimal(28, 10)) / CAST(12 AS decimal(28, 10)), 10) END AS decimal(19, 10)) AS share_rounded
    FROM #pk AS k
    JOIN #t AS t ON t.profile_key = k.profile_key
    LEFT JOIN #ye AS ye ON ye.profile_key = k.profile_key
    CROSS JOIN (VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12)) AS n (period_no)
    LEFT JOIN #m AS m ON m.profile_key = k.profile_key AND m.period_no = n.period_no
), f AS (
    SELECT s.*,
           CAST(CASE WHEN s.period_no < 12 THEN s.share_rounded
                     ELSE 1 - SUM(CASE WHEN s.period_no < 12 THEN s.share_rounded END) OVER (PARTITION BY s.profile_key) END
                AS decimal(19, 10)) AS share
    FROM s
)
INSERT INTO dw.plan_phasing_profile
    (profile_key, profile_basis, financial_year, prior_financial_year, year_end_release_key, sr_group_key, organisation_code,
     control_budget_detail, economic_budget, measure, period_no, period_key, share, method, prior_period_amount,
     prior_year_total, has_negative_share, is_derived)
SELECT f.profile_key, f.profile_basis, f.financial_year, f.prior_financial_year, f.year_end_release_key, f.sr_group_key,
       f.organisation_code, f.control_budget_detail, f.economic_budget, f.measure, f.period_no, f.period_key, f.share, f.method,
       CASE WHEN f.method = 'flat_no_prior_year' THEN NULL ELSE ISNULL(f.prior_period_amount, 0) END,
       CASE WHEN f.method = 'flat_no_prior_year' THEN NULL ELSE f.prior_year_total END,
       CAST(MAX(CASE WHEN f.share < 0 THEN 1 ELSE 0 END) OVER (PARTITION BY f.profile_key) AS bit),
       CAST(1 AS bit)
FROM f;
GO

CREATE UNIQUE INDEX ux_dw_plan_phasing_profile_natural ON dw.plan_phasing_profile
    (financial_year, profile_basis, sr_group_key, organisation_code, control_budget_detail, economic_budget, measure, period_no);
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'DERIVED, not published. Monthly shares for spreading an annual plan, from the prior year''s outturn as at its year-end release (or flat twelfths, with the method recorded). Shares add up to exactly 1 per profile. Never part of a real total.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'plan_phasing_profile';
GO

DROP TABLE IF EXISTS #pk;
DROP TABLE IF EXISTS #ye;
DROP TABLE IF EXISTS #m;
DROP TABLE IF EXISTS #t;
GO
