-- The model's view layer, part 7: the statement line dimension and the account dimension that points at it.
--   dw.v_model_statement_line  dw.statement_line (authored layout, no amount)
--   dw.v_model_account         dw.dim_account plus statement_line_key, the detail line of the statement that the
--                              account belongs to (dw.account_statement_line). It used to be defined in 701; it moved
--                              here because it now reads a table that 740 builds. A plain join, one row per account.

DROP VIEW IF EXISTS dw.v_model_statement_line;
GO
CREATE VIEW dw.v_model_statement_line
AS
SELECT line_key, line_id, label, label_indented, line_type, sign_presentation, indent_level, sort_order, plan_scope,
       members, detail_line_keys
FROM dw.statement_line;
GO

DROP VIEW IF EXISTS dw.v_model_account;
GO
CREATE VIEW dw.v_model_account
AS
SELECT a.account_key, a.economic_category_code, a.economic_category_name, a.economic_category_label,
       a.pesa_economic_group_code, a.pesa_economic_group, a.economic_budget, a.flow, a.flow_basis, a.source_codes,
       a.first_release, a.last_release, s.line_key AS statement_line_key
FROM dw.dim_account AS a
JOIN dw.account_statement_line AS s ON s.account_key = a.account_key;
GO
