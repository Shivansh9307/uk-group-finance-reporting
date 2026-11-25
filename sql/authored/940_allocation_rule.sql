-- scope: full
-- authored.allocation_rule: AUTHORED, not source data and not a government policy. The one rule by which I spread a real
-- shared-cost pool across departments in proportion to their payroll full-time equivalent. It names the pool, the basis, the
-- years it applies to and the least coverage a department needs to take part. It holds no amount: the pool amount is read from
-- the real outturn (dw.fact_outturn) when dw.allocation_pool is built, and nothing here is added to any real total.
-- Register: README.md, "Register of real, authored, derived and synthetic data". Data dictionary: docs/data-dictionary/allocation.md.
--
--   pool_department_number           the department of the current structure whose outturn is the pool (010 Cabinet Office)
--   pool_control_budget_detail_code  the OSCAR control budget detail of the pool (DEL ADMIN: the administration budget of DEL)
--   basis                            the weight of a department is its payroll full-time equivalent over the sum of the departments taking part
--   first_financial_year, last_financial_year   the closed financial years the rule applies to; 2026-27 is a part year and is not allocated
--   min_months                       a department takes part in a year only with a valid payroll cell in at least this many of its 12 months
--   rounding_rule                    how the allocated amounts are made to add up to the pool exactly

DROP TABLE IF EXISTS authored.allocation_rule;
GO

CREATE TABLE authored.allocation_rule (
    rule_id                          varchar(30)    NOT NULL CONSTRAINT pk_authored_allocation_rule PRIMARY KEY,
    rule_name                        nvarchar(100)  NOT NULL,
    pool_department_number           nvarchar(10)   NOT NULL,
    pool_control_budget_detail_code  nvarchar(30)   NOT NULL,
    pool_description                 nvarchar(600)  NOT NULL,
    basis                            varchar(30)    NOT NULL,
    first_financial_year             varchar(7)     NOT NULL,
    last_financial_year              varchar(7)     NOT NULL,
    min_months                       int            NOT NULL,
    rounding_rule                    nvarchar(600)  NOT NULL,
    rationale                        nvarchar(1200) NOT NULL,
    not_this                         nvarchar(1200) NOT NULL,
    data_class                       varchar(20)    NOT NULL,
    CONSTRAINT ck_authored_allocation_rule_class CHECK (data_class = 'authored'),
    CONSTRAINT ck_authored_allocation_rule_basis CHECK (basis = 'payroll_fte'),
    CONSTRAINT ck_authored_allocation_rule_months CHECK (min_months BETWEEN 1 AND 12)
);
GO

INSERT INTO authored.allocation_rule
    (rule_id, rule_name, pool_department_number, pool_control_budget_detail_code, pool_description, basis,
     first_financial_year, last_financial_year, min_months, rounding_rule, rationale, not_this, data_class)
VALUES
    ('CO_ADMIN_FTE',
     N'Cabinet Office administration spend, spread by payroll full-time equivalent',
     N'010', N'DEL ADMIN',
     N'The outturn of the Cabinet Office (department 010 of the current structure) in the control budget detail DEL ADMIN (the administration budget of departmental expenditure limits), in GBP thousands, spending positive, all economic categories, the latest view of each financial year (the sum of the revision deltas of every release).',
     'payroll_fte',
     '2018-19', '2025-26', 9,
     N'The allocated amount of each department is the pool times its payroll full-time equivalent over the sum of the departments taking part, rounded to four decimal places (GBP thousands, so to ten pence). The rounding remainder is added to the department with the largest weight (the lower department number on a tie), so that the allocated amounts add up to the pool exactly, and it is stored and shown on the row it lands on.',
     N'The Cabinet Office is the central department of the civil service and its administration budget is the nearest real line to a cost of running central services that every department benefits from. A shared cost has to be spread on a basis; the number of people a department employs is the plainest one and the one the workforce files give for every department that publishes them. This is my own allocation to show a weighted many-to-many allocation in the model. It is not a recharge that government makes.',
     N'It is not a government policy, a recharge or a charge that any department pays. The Cabinet Office administration budget is mostly the Cabinet Office''s own running costs, and I do not claim that it is a shared service pool in the accounting sense. Only departments that publish workforce files take part, so the Home Office, the Ministry of Justice and the Cabinet Office itself are not in the weights (the workforce source does not hold them), and a department with too few months of data is left out of the year and listed with the weight it would have had.',
     'authored');
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'AUTHORED: my own allocation rule (not a government policy). Names a real pool (Cabinet Office DEL administration outturn), the basis (payroll full-time equivalent), the years and the minimum months of data. Holds no amount; never part of a real total.',
    @level0type = N'SCHEMA', @level0name = N'authored', @level1type = N'TABLE', @level1name = N'allocation_rule';
GO
