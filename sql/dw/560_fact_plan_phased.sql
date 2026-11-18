-- dw.fact_plan_phased: every dw.fact_plan row spread over periods 1 to 12 with its phasing profile. DERIVED.
--   One row per plan row and period: plan_fact_key x period_no. scenario_key is 'Plan (phased)' of dw.dim_scenario.
--   amount = ROUND(plan amount x share, 4) for periods 1 to 11; period 12 takes the remainder, so the twelve rows
--   of a plan row add up exactly to the plan amount (tested to four decimals, exactly).
--   Administration rows (is_part_of_other_measure = 1) are phased too and keep the flag: they are part of resource
--   DEL and are never added to it.
--   The profile method of the plan row is carried (prior_year_outturn, flat_no_prior_year, flat_prior_not_positive).
--   Plan rows of FY2017-18 (OSCAR Plans, full scope) are not phased: the calendar and the in-year outturn start
--   with FY2018-19.
-- is_derived = 1 on every row. Nothing else reads this table.

DROP TABLE IF EXISTS dw.fact_plan_phased;
GO

CREATE TABLE dw.fact_plan_phased (
    plan_fact_key             int            NOT NULL,
    period_no                 tinyint        NOT NULL,
    plan_source_key           int            NOT NULL,
    financial_year            varchar(7)     NOT NULL,
    sr_group_key              int            NOT NULL,
    organisation_code         nvarchar(50)   NULL,
    control_budget_detail     varchar(30)    NOT NULL,
    economic_budget           varchar(20)    NOT NULL,
    measure                   varchar(40)    NOT NULL,
    grain_code                char(1)        NOT NULL,
    is_part_of_other_measure  bit            NOT NULL,
    profile_key               int            NOT NULL,
    period_key                int            NOT NULL,
    scenario_key              int            NOT NULL,
    share                     decimal(19,10) NOT NULL,
    amount                    decimal(19,4)  NOT NULL,
    method                    varchar(30)    NOT NULL,
    is_derived                bit            NOT NULL,
    CONSTRAINT pk_dw_fact_plan_phased PRIMARY KEY (plan_fact_key, period_no)
);
GO

WITH x AS (
    SELECT p.plan_fact_key, pr.period_no, p.plan_source_key, p.financial_year, p.sr_group_key, p.organisation_code,
           p.control_budget_detail, p.economic_budget, p.measure, p.grain_code, p.is_part_of_other_measure,
           pr.profile_key, pr.period_key, pr.share, pr.method, p.amount AS plan_amount,
           CAST(ROUND(p.amount * pr.share, 4) AS decimal(19, 4)) AS rounded
    FROM dw.fact_plan AS p
    JOIN dw.plan_phasing_profile AS pr
      ON pr.financial_year = p.financial_year AND pr.measure = p.measure AND pr.sr_group_key = p.sr_group_key
     AND pr.profile_basis = CASE WHEN p.grain_code = 'A' THEN 'organisation' ELSE 'group' END
     AND ISNULL(pr.organisation_code, N'') = CASE WHEN p.grain_code = 'A' THEN ISNULL(p.organisation_code, N'') ELSE N'' END
     AND ISNULL(pr.control_budget_detail, '') = CASE WHEN p.grain_code = 'A' THEN p.control_budget_detail ELSE '' END
     AND ISNULL(pr.economic_budget, '') = CASE WHEN p.grain_code = 'A' THEN p.economic_budget ELSE '' END
)
INSERT INTO dw.fact_plan_phased
    (plan_fact_key, period_no, plan_source_key, financial_year, sr_group_key, organisation_code, control_budget_detail,
     economic_budget, measure, grain_code, is_part_of_other_measure, profile_key, period_key, scenario_key, share, amount,
     method, is_derived)
SELECT x.plan_fact_key, x.period_no, x.plan_source_key, x.financial_year, x.sr_group_key, x.organisation_code,
       x.control_budget_detail, x.economic_budget, x.measure, x.grain_code, x.is_part_of_other_measure,
       x.profile_key, x.period_key,
       (SELECT scenario_key FROM dw.dim_scenario WHERE scenario_name = N'Plan (phased)'),
       x.share,
       CAST(CASE WHEN x.period_no < 12 THEN x.rounded
                 ELSE x.plan_amount - SUM(CASE WHEN x.period_no < 12 THEN x.rounded END) OVER (PARTITION BY x.plan_fact_key) END
            AS decimal(19, 4)),
       x.method, CAST(1 AS bit)
FROM x;
GO

CREATE INDEX ix_dw_fact_plan_phased_period ON dw.fact_plan_phased (financial_year, period_key, sr_group_key, measure);
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'DERIVED, not published. Each annual plan row spread over periods 1 to 12 with its phasing profile; the twelve rows of a plan row add up exactly to the plan amount. Scenario Plan (phased). Never part of a real total; nothing else reads it.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'fact_plan_phased';
GO
