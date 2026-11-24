-- scope: full
-- The views the semantic model reads for the NHS trust accounts, part 1: the dimensions.
--   dw.v_model_tac_provider         dw.tac_provider with its department key (the Department of Health and Social
--                                   Care), a reporting status and the successor
--   dw.v_model_tac_line             dw.tac_statutory_line with the derived cash-flow line a published line is compared with
--   dw.v_model_tac_cash_flow_line   dw.tac_cash_flow_line plus the member 0 'Not compared', so that every statement
--                                   line has a key that exists
--   dw.v_model_tac_control_line     dw.tac_control_line
--   dw.v_model_tac_control_member   dw.tac_control_member
-- The files sit in the audit layer because dw.tac_provider_group is built there (the department dimension is built
-- after sql/dw/100). A view is a plain select of the columns the model needs; the business names are in the model.

DROP VIEW IF EXISTS dw.v_model_tac_provider;
GO
CREATE VIEW dw.v_model_tac_provider
AS
SELECT p.provider_key, p.provider_code, p.provider_name, p.provider_type, p.region, p.sector,
       g.department_key,
       p.first_data_release, p.last_data_release, p.n_data_years,
       CAST(CASE WHEN p.last_data_release IS NULL THEN 'No statements in any file'
                 WHEN p.last_data_release < (SELECT MAX(release) FROM dw.tac_fact) THEN 'No statements after ' + p.last_data_release
                 ELSE 'Reports in the latest file' END AS nvarchar(60)) AS reporting_status,
       p.successor_code, s.provider_name AS successor_name, p.successor_kind, p.successor_effective_date
FROM dw.tac_provider AS p
JOIN dw.tac_provider_group AS g ON g.provider_key = p.provider_key
LEFT JOIN dw.tac_provider AS s ON s.provider_key = p.successor_provider_key;
GO

DROP VIEW IF EXISTS dw.v_model_tac_cash_flow_line;
GO
CREATE VIEW dw.v_model_tac_cash_flow_line
AS
SELECT cash_flow_line_key, line_code, label, section, MIN(sort_order) OVER (PARTITION BY section) AS section_order,
       sort_order, line_kind, note
FROM dw.tac_cash_flow_line
UNION ALL
SELECT 0, 'NOT_COMPARED', N'Not compared', N'Not compared', 0, 0, 'not_compared',
       N'Not a cash-flow line: the member that every balance-sheet, income-statement and cash-flow subtotal line points at, so that every line of the statement dimension has a key.';
GO

DROP VIEW IF EXISTS dw.v_model_tac_line;
GO
CREATE VIEW dw.v_model_tac_line
AS
SELECT l.line_key, l.statement,
       CAST(CASE l.statement WHEN 'SoCI' THEN 'Income statement' WHEN 'SoFP' THEN 'Balance sheet' ELSE 'Cash flow' END AS nvarchar(40)) AS statement_name,
       CAST(CASE l.statement WHEN 'SoCI' THEN 1 WHEN 'SoFP' THEN 2 ELSE 3 END AS int) AS statement_order,
       l.sub_code, l.description, CAST(CONCAT(l.description, N' (', l.sub_code, N')') AS nvarchar(450)) AS line_label, l.section,
       MIN(l.line_key) OVER (PARTITION BY l.statement, l.section) AS section_order,
       l.line_kind, l.expected_sign,
       ISNULL(c.cash_flow_line_key, 0) AS cash_flow_line_key
FROM dw.tac_statutory_line AS l
LEFT JOIN dw.tac_cash_flow_comparison AS c ON c.line_key = l.line_key;
GO

DROP VIEW IF EXISTS dw.v_model_tac_control_line;
GO
CREATE VIEW dw.v_model_tac_control_line
AS
SELECT control_line_key, control_line, label, statement, nature, note
FROM dw.tac_control_line;
GO

DROP VIEW IF EXISTS dw.v_model_tac_control_member;
GO
CREATE VIEW dw.v_model_tac_control_member
AS
SELECT control_line_key, line_key
FROM dw.tac_control_member;
GO
