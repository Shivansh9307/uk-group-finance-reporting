-- dw.plan_measure_selection and dw.outturn_plan_line: the two objects that put in-year outturn on the plan's
-- measures. Both feed the phasing profile (dw/555) and the in-year plan-basis outturn (dw/570).
--
-- dw.plan_measure_selection says which outturn lines each plan measure is. One row per measure and control
-- budget detail. It is a definition (written here as values), not data:
--   RDEL           DEL programme and administration, resource, depreciation included (OSCAR Plans)
--   RDEL_EX_DEPN   the same, leaving out the economic group DEPRECIATION (Estimates)
--   CDEL           DEL programme and administration, capital
--   RAME, CAME     departmental AME, resource and capital
--   ADMIN          DEL administration, resource (administration budgets are resource budgets)
--   ADMIN_EX_DEPN  the same without the DEPRECIATION group
-- The in-year files have no ringfence column, so excluding depreciation can only drop the DEPRECIATION economic
-- group; the exact basis is dw.fact_outturn_annual's basis_rdel_excl_depreciation (dw/575).
--
-- dw.outturn_plan_line: the revision deltas of dw.fact_outturn summed to release x period x organisation x
-- control budget detail x economic budget x depreciation flag, with the Spending Review group of the line from
-- dw.outturn_sr_group_bridge and the department number as the release reported it. Real amounts, regrouped; the
-- sum of amount_delta is the sum of dw.fact_outturn (tested).
--   economic_budget   RESOURCE, CAPITAL, or n/a for anything else
--   is_depreciation   the economic category is in the PESA economic group DEPRECIATION
--   reported_department_number   the department number of the release's own structure (for the combined pre-2023 group)
--   sr_group_key        the group of the current structure (the bridge); the phasing profile reads this column
--   plan_sr_group_key   the group the plan of that year is published under: the same, except that FY2022-23 outturn of
--                       the departments 013, 048 and 084 as the release reported them goes to the combined pre-2023
--                       group, because the FY2022-23 plan exists only for BEIS, DCMS and DIT as one group
--                       (dw.plan_group_rule). The model and the in-year plan-basis outturn read this column, so that
--                       the plan and the outturn of a group are on one structure.
--
-- dw.plan_group_rule: the definition behind plan_sr_group_key. One row per financial year and department number as
-- reported, from authored/department_sr_group.csv (basis pre2023_as_reported) and the combined member of
-- dw.dim_sr_group. No amount; a mapping.

DROP TABLE IF EXISTS dw.plan_measure_selection;
DROP TABLE IF EXISTS dw.outturn_plan_line;
DROP TABLE IF EXISTS dw.plan_group_rule;
GO

CREATE TABLE dw.plan_group_rule (
    financial_year      varchar(7)    NOT NULL,
    department_number   nvarchar(10)  NOT NULL,
    plan_sr_group_key   int           NOT NULL,
    rule_note           nvarchar(300) NOT NULL,
    CONSTRAINT pk_dw_plan_group_rule PRIMARY KEY (financial_year, department_number),
    CONSTRAINT fk_dw_plan_group_rule_group FOREIGN KEY (plan_sr_group_key) REFERENCES dw.dim_sr_group (sr_group_key)
);
GO

INSERT INTO dw.plan_group_rule (financial_year, department_number, plan_sr_group_key, rule_note)
SELECT '2022-23', r.department_number, g.sr_group_key,
       N'The FY2022-23 plan is published for BEIS, DCMS and DIT as one group, so their outturn as the release reported it goes to the same group.'
FROM stg.department_sr_group AS r
CROSS JOIN dw.dim_sr_group AS g
WHERE r.basis = 'pre2023_as_reported' AND g.member_type = 'combined_pre_2023';
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'Which Spending Review group the plan of a financial year is published under for outturn of a department number as reported, where that differs from the current-structure bridge (FY2022-23: BEIS, DCMS and DIT as one group). A mapping, no amounts.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'plan_group_rule';
GO

CREATE TABLE dw.plan_measure_selection (
    measure                varchar(40)  NOT NULL,
    control_budget_detail  varchar(30)  NOT NULL,
    economic_budget        varchar(20)  NOT NULL,
    excludes_depreciation  bit          NOT NULL,
    CONSTRAINT pk_dw_plan_measure_selection PRIMARY KEY (measure, control_budget_detail)
);
GO

INSERT INTO dw.plan_measure_selection (measure, control_budget_detail, economic_budget, excludes_depreciation)
VALUES
 ('RDEL',          'DEL PROG',  'RESOURCE', 0), ('RDEL',          'DEL ADMIN', 'RESOURCE', 0),
 ('RDEL_EX_DEPN',  'DEL PROG',  'RESOURCE', 1), ('RDEL_EX_DEPN',  'DEL ADMIN', 'RESOURCE', 1),
 ('CDEL',          'DEL PROG',  'CAPITAL',  0), ('CDEL',          'DEL ADMIN', 'CAPITAL',  0),
 ('RAME',          'DEPT AME',  'RESOURCE', 0),
 ('CAME',          'DEPT AME',  'CAPITAL',  0),
 ('ADMIN',         'DEL ADMIN', 'RESOURCE', 0),
 ('ADMIN_EX_DEPN', 'DEL ADMIN', 'RESOURCE', 1);
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'Which outturn lines each plan measure is: control budget detail, economic budget, and whether the DEPRECIATION group is left out. A definition, no amounts.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'plan_measure_selection';
GO

CREATE TABLE dw.outturn_plan_line (
    release_key                  int           NOT NULL,
    financial_year               varchar(7)    NOT NULL,
    period_key                   int           NOT NULL,
    period_no                    tinyint       NOT NULL,
    organisation_key             int           NOT NULL,
    organisation_code            nvarchar(50)  NOT NULL,
    reported_department_number   nvarchar(10)  NOT NULL,
    sr_group_key                 int           NOT NULL,
    plan_sr_group_key            int           NOT NULL,
    control_budget_detail        varchar(30)   NOT NULL,
    economic_budget              varchar(20)   NOT NULL,
    is_depreciation              bit           NOT NULL,
    amount_delta                 decimal(19,4) NOT NULL
);
GO

INSERT INTO dw.outturn_plan_line
    (release_key, financial_year, period_key, period_no, organisation_key, organisation_code, reported_department_number,
     sr_group_key, plan_sr_group_key, control_budget_detail, economic_budget, is_depreciation, amount_delta)
SELECT f.release_key, p.financial_year, f.period_key, p.period, f.organisation_key, o.organisation_code, rd.department_number,
       b.sr_group_key, COALESCE(gr.plan_sr_group_key, b.sr_group_key), cb.control_budget_detail_code,
       CAST(CASE WHEN a.economic_budget IN ('RESOURCE', 'CAPITAL') THEN a.economic_budget ELSE 'n/a' END AS varchar(20)),
       CAST(CASE WHEN a.pesa_economic_group_code = 'DEPRECIATION' THEN 1 ELSE 0 END AS bit),
       SUM(f.amount_delta)
FROM dw.fact_outturn AS f
JOIN dw.dim_segment AS sg ON sg.segment_key = f.segment_key
JOIN dw.outturn_sr_group_bridge AS b ON b.organisation_key = f.organisation_key AND b.sub_segment_code = sg.sub_segment_code
JOIN dw.dim_period AS p ON p.period_key = f.period_key
JOIN dw.dim_organisation AS o ON o.organisation_key = f.organisation_key
JOIN dw.dim_department AS rd ON rd.department_key = f.department_key
LEFT JOIN dw.plan_group_rule AS gr ON gr.financial_year = p.financial_year AND gr.department_number = rd.department_number
JOIN dw.dim_account AS a ON a.account_key = f.account_key
JOIN dw.dim_control_budget AS cb ON cb.control_budget_key = f.control_budget_key
GROUP BY f.release_key, p.financial_year, f.period_key, p.period, f.organisation_key, o.organisation_code, rd.department_number,
         b.sr_group_key, COALESCE(gr.plan_sr_group_key, b.sr_group_key), cb.control_budget_detail_code,
         CASE WHEN a.economic_budget IN ('RESOURCE', 'CAPITAL') THEN a.economic_budget ELSE 'n/a' END,
         CASE WHEN a.pesa_economic_group_code = 'DEPRECIATION' THEN 1 ELSE 0 END;
GO

CREATE CLUSTERED INDEX cx_dw_outturn_plan_line ON dw.outturn_plan_line (financial_year, release_key, sr_group_key);
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'Revision deltas of dw.fact_outturn at release x period x organisation x control budget detail x economic budget x depreciation flag, with the Spending Review group from the bridge. Real amounts regrouped; the working table behind the phasing profile and the in-year plan-basis outturn.',
    @level0type = N'SCHEMA', @level0name = N'dw', @level1type = N'TABLE', @level1name = N'outturn_plan_line';
GO
