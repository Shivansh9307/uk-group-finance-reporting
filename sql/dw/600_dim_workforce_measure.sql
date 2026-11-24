-- scope: full
-- dw.dim_workforce_measure: the measures of dw.workforce_month, and for each one which published columns it is read
-- from, in order of preference (dw.workforce_measure_rule). Definitional (a rule, not source data), so it is written
-- here and not in authored/.
--   priority  1 = the file's own total; 2 and 3 = rebuilt from the file's components when the total is blank
--   raw_key   the measure key the reader gave the column (pipeline/src/ukfr/readers/workforce.py)
-- Contingent labour is the non-payroll staff the files count as agency, interim, specialist or other contingent
-- workers. It is not the older templates' "total non-payroll" figure, which also counted consultants (the newer
-- template reports consultancy as a number of contracts, not people), so a series built from this measure has one
-- definition over the whole period. The old total is not used.

DROP TABLE IF EXISTS dw.workforce_month;
DROP TABLE IF EXISTS dw.workforce_measure_rule;
DROP TABLE IF EXISTS dw.dim_workforce_measure;
GO

CREATE TABLE dw.dim_workforce_measure (
    measure_key    varchar(40)   NOT NULL CONSTRAINT pk_dw_dim_workforce_measure PRIMARY KEY,
    measure_name   nvarchar(100) NOT NULL,
    measure_group  varchar(20)   NOT NULL,   -- workforce | paybill | cost
    unit           varchar(10)   NOT NULL,   -- people | GBP
    definition     nvarchar(400) NOT NULL
);
INSERT INTO dw.dim_workforce_measure (measure_key, measure_name, measure_group, unit, definition) VALUES
 ('payroll_headcount', N'Payroll headcount', 'workforce', 'people', N'Payroll staff in post, headcount, as published'),
 ('payroll_fte', N'Payroll full-time equivalent', 'workforce', 'people', N'Payroll staff in post, full-time equivalent, as published'),
 ('contingent_headcount', N'Contingent labour headcount', 'workforce', 'people', N'Agency, interim, specialist and other contingent workers, headcount; consultants are not included'),
 ('contingent_fte', N'Contingent labour full-time equivalent', 'workforce', 'people', N'Agency, interim, specialist and other contingent workers, full-time equivalent; consultants are not included'),
 ('payroll_paybill_gbp', N'Payroll paybill', 'paybill', 'GBP', N'Total monthly paybill for payroll staff: salary, allowances, performance payments, overtime, employer pension and national insurance'),
 ('payroll_salary_gbp', N'Payroll salary', 'paybill', 'GBP', N'Salary within payroll paybill'),
 ('payroll_allowances_gbp', N'Payroll allowances', 'paybill', 'GBP', N'Allowances within payroll paybill'),
 ('payroll_non_consolidated_gbp', N'Payroll non-consolidated performance payments', 'paybill', 'GBP', N'Non-consolidated performance payments within payroll paybill'),
 ('payroll_overtime_gbp', N'Payroll overtime', 'paybill', 'GBP', N'Overtime within payroll paybill'),
 ('payroll_employer_pension_gbp', N'Payroll employer pension contributions', 'paybill', 'GBP', N'Employer pension contributions within payroll paybill'),
 ('payroll_employer_ni_gbp', N'Payroll employer national insurance', 'paybill', 'GBP', N'Employer national insurance contributions within payroll paybill'),
 ('contingent_labour_cost_gbp', N'Contingent labour cost', 'cost', 'GBP', N'Monthly cost of agency, interim and specialist staff as published'),
 ('consultancy_cost_gbp', N'Consultancy cost', 'cost', 'GBP', N'Monthly cost of consultants and consultancy as published'),
 ('non_payroll_cost_gbp', N'Non-payroll staff cost', 'cost', 'GBP', N'Contingent labour plus consultancy cost as published'),
 ('staff_cost_total_gbp', N'Total staff cost', 'cost', 'GBP', N'Payroll paybill plus non-payroll cost as published');
GO

CREATE TABLE dw.workforce_measure_rule (
    measure_key  varchar(40) NOT NULL,
    priority     tinyint     NOT NULL,
    raw_key      varchar(60) NOT NULL,
    CONSTRAINT pk_dw_workforce_measure_rule PRIMARY KEY (measure_key, priority, raw_key),
    CONSTRAINT fk_dw_workforce_measure_rule FOREIGN KEY (measure_key) REFERENCES dw.dim_workforce_measure (measure_key)
);
INSERT INTO dw.workforce_measure_rule (measure_key, priority, raw_key) VALUES
 ('payroll_headcount', 1, 'payroll_total_hc'),
 ('payroll_headcount', 2, 'payroll_ao_aa_hc'), ('payroll_headcount', 2, 'payroll_eo_hc'),
 ('payroll_headcount', 2, 'payroll_seo_heo_hc'), ('payroll_headcount', 2, 'payroll_grade_6_7_hc'),
 ('payroll_headcount', 2, 'payroll_scs_hc'), ('payroll_headcount', 2, 'payroll_other_hc'),
 ('payroll_fte', 1, 'payroll_total_fte'),
 ('payroll_fte', 2, 'payroll_ao_aa_fte'), ('payroll_fte', 2, 'payroll_eo_fte'),
 ('payroll_fte', 2, 'payroll_seo_heo_fte'), ('payroll_fte', 2, 'payroll_grade_6_7_fte'),
 ('payroll_fte', 2, 'payroll_scs_fte'), ('payroll_fte', 2, 'payroll_other_fte'),
 ('contingent_headcount', 1, 'np_contingent_total_hc'),
 ('contingent_headcount', 2, 'np_agency_hc'), ('contingent_headcount', 2, 'np_interim_hc'),
 ('contingent_headcount', 2, 'np_specialist_hc'),
 ('contingent_headcount', 3, 'np_admin_clerical_hc'), ('contingent_headcount', 3, 'np_interim_specialist_hc'),
 ('contingent_headcount', 3, 'np_other_contingent_hc'),
 ('contingent_fte', 1, 'np_contingent_total_fte'),
 ('contingent_fte', 2, 'np_agency_fte'), ('contingent_fte', 2, 'np_interim_fte'), ('contingent_fte', 2, 'np_specialist_fte'),
 ('contingent_fte', 3, 'np_admin_clerical_fte'), ('contingent_fte', 3, 'np_interim_specialist_fte'),
 ('contingent_fte', 3, 'np_other_contingent_fte'),
 ('payroll_paybill_gbp', 1, 'cost_payroll_paybill_gbp'),
 ('payroll_paybill_gbp', 2, 'cost_salary_gbp'), ('payroll_paybill_gbp', 2, 'cost_allowances_gbp'),
 ('payroll_paybill_gbp', 2, 'cost_non_consolidated_gbp'), ('payroll_paybill_gbp', 2, 'cost_overtime_gbp'),
 ('payroll_paybill_gbp', 2, 'cost_employer_pension_gbp'), ('payroll_paybill_gbp', 2, 'cost_employer_ni_gbp'),
 ('payroll_salary_gbp', 1, 'cost_salary_gbp'),
 ('payroll_allowances_gbp', 1, 'cost_allowances_gbp'),
 ('payroll_non_consolidated_gbp', 1, 'cost_non_consolidated_gbp'),
 ('payroll_overtime_gbp', 1, 'cost_overtime_gbp'),
 ('payroll_employer_pension_gbp', 1, 'cost_employer_pension_gbp'),
 ('payroll_employer_ni_gbp', 1, 'cost_employer_ni_gbp'),
 ('contingent_labour_cost_gbp', 1, 'cost_contingent_gbp'),
 ('consultancy_cost_gbp', 1, 'cost_consultancy_gbp'),
 ('non_payroll_cost_gbp', 1, 'cost_non_payroll_total_gbp'),
 ('staff_cost_total_gbp', 1, 'cost_grand_total_gbp');
GO
