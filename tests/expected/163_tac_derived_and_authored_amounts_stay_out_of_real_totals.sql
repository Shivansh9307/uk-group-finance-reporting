-- requires: dw.tac_fact
-- Independent of the model: each total from its own warehouse table. TAC Amount adds the current-year column of the lines
-- of kind line of the income statement and the cash flow.
SELECT CAST((SELECT SUM(value) FROM dw.tac_fact) AS decimal(38, 4)) AS fact_tac_value,
       CAST((SELECT SUM(f.value) FROM dw.tac_fact AS f JOIN dw.tac_statutory_line AS l ON l.line_key = f.line_key
             WHERE f.period_column = 'CY' AND l.statement <> 'SoFP' AND l.line_kind = 'line') AS decimal(38, 4)) AS tac_amount_all_years,
       CAST((SELECT SUM(amount_delta) FROM dw.fact_outturn) AS decimal(38, 4)) AS outturn,
       CAST((SELECT SUM(amount) FROM dw.tac_cash_flow_derived) AS decimal(38, 4)) AS derived_cash_flow,
       CAST((SELECT SUM(amount) FROM dw.tac_consolidated_control) AS decimal(38, 4)) AS consolidated_amount;
