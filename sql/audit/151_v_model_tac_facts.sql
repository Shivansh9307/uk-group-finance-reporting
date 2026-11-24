-- scope: full
-- The views the semantic model reads for the NHS trust accounts, part 2: the facts.
--   dw.v_model_tac_fact              dw.tac_fact, every row, with the year as the number it starts in and, on a
--                                    prior-year row, the restatement: the prior-year value of year Y less the
--                                    current-year value of year Y-1 for the same provider and line, where the two
--                                    differ by GBP 1,000 or more (the rule of audit.tac_prior_year_difference)
--   dw.v_model_tac_cash_flow_derived dw.tac_cash_flow_derived, every row
--   dw.v_model_tac_consolidated      dw.tac_consolidated_control, every row
-- The restatement column is a property of the pair of files, so it is written here once and the model adds it up
-- (`TAC Restatement`) instead of searching for the matching row of the year before in DAX.

DROP VIEW IF EXISTS dw.v_model_tac_fact;
GO
CREATE VIEW dw.v_model_tac_fact
AS
SELECT f.provider_key, f.line_key,
       f.release AS financial_year,
       CAST(LEFT(f.release, 4) AS int) AS release_start,
       f.period_column,
       f.reported_year,
       f.value,
       CAST(CASE WHEN f.period_column = 'PY' AND ABS(f.value - cy.value) >= 1 THEN f.value - cy.value END AS decimal(19,4)) AS restatement_amount
FROM dw.tac_fact AS f
LEFT JOIN dw.tac_fact AS cy ON f.period_column = 'PY'
                           AND cy.provider_key = f.provider_key AND cy.line_key = f.line_key
                           AND cy.period_column = 'CY' AND cy.release = f.reported_year;
GO

DROP VIEW IF EXISTS dw.v_model_tac_cash_flow_derived;
GO
CREATE VIEW dw.v_model_tac_cash_flow_derived
AS
SELECT provider_key, release AS financial_year, cash_flow_line_key, amount
FROM dw.tac_cash_flow_derived;
GO

DROP VIEW IF EXISTS dw.v_model_tac_consolidated;
GO
CREATE VIEW dw.v_model_tac_consolidated
AS
SELECT release AS financial_year, printed_line, control_line_key, statement, label, amount, amount_gbp_million,
       next_report_comparative_gbp_million, source_report, pdf_page, printed_page, note
FROM dw.tac_consolidated_control;
GO
