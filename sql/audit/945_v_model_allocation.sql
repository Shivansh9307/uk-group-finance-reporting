-- scope: full
-- The views the semantic model reads for the allocation (part 10 of the model's view layer).
--   dw.v_model_allocation_rule      the authored rule, one row: pool, basis, years, rounding and rationale (no amount)
--   dw.v_model_allocation_pool      one row per rule and year: the real pool, GBP thousands, the department it is the outturn of and the sum
--                                   of the allocated amounts of its bridge rows (the model compares the allocation in context with it)
--   dw.v_model_allocation_bridge    one row per rule, year and participating department: the weight, the allocated amount and its
--                                   rounding adjustment, the average full-time equivalent, the months present and the annualised paybill
--   dw.v_model_allocation_coverage  one row per rule and year: how many departments take part, how many are left out for too few
--                                   months and the share of the full-time equivalent they would have carried (counts and shares, no amount)
-- DERIVED from real data: the pool is the real outturn, the weights are real payroll full-time equivalent, the allocation is mine
-- (sql/audit/940). Nothing synthetic is read: the what-if setting view is in sql/dw/940 and reads the synthetic table only.

DROP VIEW IF EXISTS dw.v_model_allocation_rule;
GO
DROP VIEW IF EXISTS dw.v_model_allocation_pool;
GO
DROP VIEW IF EXISTS dw.v_model_allocation_bridge;
GO
DROP VIEW IF EXISTS dw.v_model_allocation_coverage;
GO

CREATE VIEW dw.v_model_allocation_rule
AS
SELECT r.rule_id, r.rule_name, r.pool_department_number, r.pool_control_budget_detail_code, r.pool_description, r.basis,
       r.first_financial_year, r.last_financial_year, r.min_months, r.rounding_rule, r.rationale, r.not_this
FROM authored.allocation_rule AS r;
GO

CREATE VIEW dw.v_model_allocation_pool
AS
SELECT p.pool_key, p.rule_id, p.financial_year, p.pool_department_key AS department_key, p.pool_amount, p.pool_rows,
       (SELECT SUM(f.allocated_amount) FROM dw.fact_allocation AS f WHERE f.pool_key = p.pool_key) AS allocated_total
FROM dw.allocation_pool AS p;
GO

CREATE VIEW dw.v_model_allocation_bridge
AS
SELECT f.pool_key, f.department_key, f.rule_id, f.financial_year, f.weight, f.allocated_amount, f.rounding_adjustment,
       f.is_rounding_row, f.avg_fte, f.months_present, f.paybill_annualised
FROM dw.fact_allocation AS f;
GO

CREATE VIEW dw.v_model_allocation_coverage
AS
SELECT s.rule_id, s.financial_year, s.participants, s.too_few_months_departments, s.too_few_months_weight_share,
       s.no_workforce_departments
FROM audit.allocation_year_summary AS s;
GO
