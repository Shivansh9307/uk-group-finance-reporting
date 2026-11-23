-- dw.outturn_plan_basis_inyear: in-year outturn on the plan's measures, by Spending Review group and month.
--   Grain: release x financial year x period x Spending Review group x measure. amount is the outturn of that
--   period AS AT that release: the running sum of the revision deltas of the release's financial year up to and
--   including the release (so it equals what the release reports). Rows whose amount is exactly zero are not kept.
--   The group is the one the plan is published under (dw.outturn_plan_line.plan_sr_group_key): the current structure from
--   dw.outturn_sr_group_bridge, except FY2022-23 outturn of the departments 013, 048 and 084 as reported, which goes to the
--   combined pre-2023 group (dw.plan_group_rule). The measure comes from dw.plan_measure_selection. Period 0 (June 2019, not allocated to a month) is kept: it is in the year total.
--   RDEL, RDEL_EX_DEPN, CDEL, RAME, CAME, ADMIN and ADMIN_EX_DEPN overlap by design (ADMIN is part of RDEL, and
--   RDEL_EX_DEPN is RDEL less one economic group); never add measures together.
--   basis_note: the in-year files have no ringfence column, so the measures that exclude depreciation drop only the
--   economic group DEPRECIATION. Other non-cash items stay in, about 5.5bn a year from 2024-25 at resource DEL
--   (audit.pss_vs_outturn, full scope). The exact basis is dw.outturn_plan_basis_annual.
-- Real outturn, regrouped; nothing estimated and nothing derived from a plan.

DROP TABLE IF EXISTS dw.outturn_plan_basis_inyear;
GO

CREATE TABLE dw.outturn_plan_basis_inyear (
    release_key          int            NOT NULL,
    financial_year       varchar(7)     NOT NULL,
    period_key           int            NOT NULL,
    period_no            tinyint        NOT NULL,
    sr_group_key         int            NOT NULL,
    measure              varchar(40)    NOT NULL,
    amount               decimal(19,4)  NOT NULL,
    is_year_end_release  bit            NOT NULL,
    basis_note           varchar(300)   NOT NULL,
    CONSTRAINT pk_dw_outturn_plan_basis_inyear PRIMARY KEY (release_key, period_key, sr_group_key, measure)
);
GO

WITH d AS (
    -- the deltas of each release, by the plan's measures (a line can belong to more than one measure)
    SELECT l.release_key, l.financial_year, l.period_key, l.period_no, l.plan_sr_group_key AS sr_group_key, ms.measure, SUM(l.amount_delta) AS amount
    FROM dw.outturn_plan_line AS l
    JOIN dw.plan_measure_selection AS ms
      ON ms.control_budget_detail = l.control_budget_detail AND ms.economic_budget = l.economic_budget
     AND (ms.excludes_depreciation = 0 OR l.is_depreciation = 0)
    GROUP BY l.release_key, l.financial_year, l.period_key, l.period_no, l.plan_sr_group_key, ms.measure
), combos AS (
    SELECT DISTINCT financial_year, period_key, period_no, sr_group_key, measure FROM d
), grid AS (
    SELECT r.release_key, c.financial_year, c.period_key, c.period_no, c.sr_group_key, c.measure
    FROM combos AS c
    JOIN dw.dim_release AS r ON r.financial_year = c.financial_year
), running AS (
    SELECT g.release_key, g.financial_year, g.period_key, g.period_no, g.sr_group_key, g.measure,
           SUM(ISNULL(d.amount, 0)) OVER (PARTITION BY g.financial_year, g.period_key, g.sr_group_key, g.measure
                                          ORDER BY g.release_key ROWS UNBOUNDED PRECEDING) AS amount
    FROM grid AS g
    LEFT JOIN d ON d.release_key = g.release_key AND d.period_key = g.period_key AND d.sr_group_key = g.sr_group_key
               AND d.measure = g.measure
)
INSERT INTO dw.outturn_plan_basis_inyear
    (release_key, financial_year, period_key, period_no, sr_group_key, measure, amount, is_year_end_release, basis_note)
SELECT u.release_key, u.financial_year, u.period_key, u.period_no, u.sr_group_key, u.measure, CAST(u.amount AS decimal(19, 4)),
       r.is_year_end_release,
       CAST(CASE WHEN u.measure IN ('RDEL_EX_DEPN', 'ADMIN_EX_DEPN')
                 THEN 'In-year files have no ringfence column: only the economic group DEPRECIATION is left out, so other non-cash items stay in (about 5.5bn a year from 2024-25). Exact basis: dw.outturn_plan_basis_annual.'
                 ELSE 'Exact selection of control budget detail and economic budget; no ringfence needed.' END AS varchar(300))
FROM running AS u
JOIN dw.dim_release AS r ON r.release_key = u.release_key
WHERE u.amount <> 0;
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'In-year outturn on the plan''s measures by Spending Review group (current structure) and month, as at each release. Real amounts regrouped. Measures overlap; never add them. The excluding-depreciation measures drop only the DEPRECIATION group (no ringfence column in the in-year files).',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'outturn_plan_basis_inyear';
GO
