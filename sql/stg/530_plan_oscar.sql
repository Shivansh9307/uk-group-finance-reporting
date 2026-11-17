-- scope: full
-- OSCAR Plans from the November 2022 annual extracts, at the load grain
--   financial year x organisation x economic category x control budget detail x economic budget.
-- Plans carry no month (every row is 'Period 0'), so there is no period in the key. Rows that net to zero
-- at this grain are kept: the count the profiling gave (8,902 for FY2019-20 to FY2021-22) includes them.
-- Control budget detail uses the same spelling as the in-year releases.
-- amount = the sum of the extract amounts (GBP thousands, whole numbers), DECIMAL(19,4).
-- department group and Spending Review group are attributes of the organisation in that year; a test
-- proves each key has exactly one of each.
-- Full scope only: the extracts are not in git.

DROP TABLE IF EXISTS stg.plan_oscar;
GO

CREATE TABLE stg.plan_oscar (
    financial_year          varchar(7)     NOT NULL,
    organisation_code       nvarchar(50)   NOT NULL,
    economic_category_code  nvarchar(50)   NOT NULL,
    control_budget_detail   varchar(30)    NOT NULL,
    economic_budget         nvarchar(50)   NOT NULL,
    department_group_code   nvarchar(50)   NOT NULL,
    sr_group_code           nvarchar(50)   NOT NULL,
    sr_group_name           nvarchar(400)  NOT NULL,
    amount                  decimal(19,4)  NOT NULL,   -- GBP thousands
    source_rows             int            NOT NULL,
    CONSTRAINT pk_stg_plan_oscar PRIMARY KEY
        (financial_year, organisation_code, economic_category_code, control_budget_detail, economic_budget)
);
GO

INSERT INTO stg.plan_oscar
    (financial_year, organisation_code, economic_category_code, control_budget_detail, economic_budget,
     department_group_code, sr_group_code, sr_group_name, amount, source_rows)
SELECT
    r.year_short_name, r.organisation_code, r.economic_category_code,
    CASE r.control_budget_l1_name
        WHEN 'DEPARTMENTAL EXPENDITURE LIMITS PROGRAMME' THEN 'DEL PROG'
        WHEN 'DEPARTMENTAL EXPENDITURE LIMITS ADMINISTRATION' THEN 'DEL ADMIN'
        WHEN 'DEPARTMENTAL ANNUALLY MANAGED EXPENDITURE' THEN 'DEPT AME'
        WHEN 'NON-DEPARTMENTAL ANNUALLY MANAGED EXPENDITURE' THEN 'NON-DEPT AME'
        WHEN 'NON-BUDGET (NB)' THEN 'NON-BUDGET'
        ELSE r.control_budget_l1_name END,
    r.economic_budget_code,
    MIN(r.department_group_code), MIN(r.sr_group_code), MIN(r.sr_group_name),
    SUM(CAST(LTRIM(RTRIM(r.amount_text)) AS decimal(19,4))),
    COUNT(*)
FROM raw.plan_oscar AS r
GROUP BY
    r.year_short_name, r.organisation_code, r.economic_category_code,
    CASE r.control_budget_l1_name
        WHEN 'DEPARTMENTAL EXPENDITURE LIMITS PROGRAMME' THEN 'DEL PROG'
        WHEN 'DEPARTMENTAL EXPENDITURE LIMITS ADMINISTRATION' THEN 'DEL ADMIN'
        WHEN 'DEPARTMENTAL ANNUALLY MANAGED EXPENDITURE' THEN 'DEPT AME'
        WHEN 'NON-DEPARTMENTAL ANNUALLY MANAGED EXPENDITURE' THEN 'NON-DEPT AME'
        WHEN 'NON-BUDGET (NB)' THEN 'NON-BUDGET'
        ELSE r.control_budget_l1_name END,
    r.economic_budget_code;
GO
