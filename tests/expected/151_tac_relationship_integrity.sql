-- requires: dw.tac_fact
-- Independent of the model: for each relationship, the rows of the many side that have no row on the one side, by
-- anti-join on dw base tables. The year dimension of the model holds the years of dw.dim_period and of the plan.
SELECT N'Fact TAC to TAC Provider' AS relationship, (SELECT COUNT_BIG(*) FROM dw.tac_fact) AS many_side_rows,
       (SELECT COUNT_BIG(*) FROM dw.tac_fact AS f WHERE NOT EXISTS (SELECT 1 FROM dw.tac_provider AS d WHERE d.provider_key = f.provider_key)) AS rows_without_member
UNION ALL
SELECT N'Fact TAC to TAC Statement Line', (SELECT COUNT_BIG(*) FROM dw.tac_fact),
       (SELECT COUNT_BIG(*) FROM dw.tac_fact AS f WHERE NOT EXISTS (SELECT 1 FROM dw.tac_statutory_line AS d WHERE d.line_key = f.line_key))
UNION ALL
SELECT N'Fact TAC to Fiscal Year', (SELECT COUNT_BIG(*) FROM dw.tac_fact),
       (SELECT COUNT_BIG(*) FROM dw.tac_fact AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_period AS d WHERE d.financial_year = f.release))
UNION ALL
SELECT N'TAC Provider to Department (current structure)', (SELECT COUNT_BIG(*) FROM dw.tac_provider),
       (SELECT COUNT_BIG(*) FROM dw.tac_provider_group AS g WHERE NOT EXISTS (SELECT 1 FROM dw.current_structure_department AS d WHERE d.department_key = g.department_key AND d.is_live = 1))
UNION ALL
SELECT N'Fact TAC Cash Flow to TAC Provider', (SELECT COUNT_BIG(*) FROM dw.tac_cash_flow_derived),
       (SELECT COUNT_BIG(*) FROM dw.tac_cash_flow_derived AS f WHERE NOT EXISTS (SELECT 1 FROM dw.tac_provider AS d WHERE d.provider_key = f.provider_key))
UNION ALL
SELECT N'Fact TAC Cash Flow to TAC Cash Flow Line', (SELECT COUNT_BIG(*) FROM dw.tac_cash_flow_derived),
       (SELECT COUNT_BIG(*) FROM dw.tac_cash_flow_derived AS f WHERE NOT EXISTS (SELECT 1 FROM dw.tac_cash_flow_line AS d WHERE d.cash_flow_line_key = f.cash_flow_line_key))
UNION ALL
SELECT N'Fact TAC Cash Flow to Fiscal Year', (SELECT COUNT_BIG(*) FROM dw.tac_cash_flow_derived),
       (SELECT COUNT_BIG(*) FROM dw.tac_cash_flow_derived AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_period AS d WHERE d.financial_year = f.release))
UNION ALL
SELECT N'TAC Statement Line to TAC Cash Flow Line', (SELECT COUNT_BIG(*) FROM dw.tac_statutory_line),
       (SELECT COUNT_BIG(*) FROM dw.tac_cash_flow_comparison AS c
        WHERE NOT EXISTS (SELECT 1 FROM dw.tac_cash_flow_line AS d WHERE d.cash_flow_line_key = c.cash_flow_line_key))
UNION ALL
SELECT N'TAC Consolidated Accounts to TAC Control Line', (SELECT COUNT_BIG(*) FROM dw.tac_consolidated_control),
       (SELECT COUNT_BIG(*) FROM dw.tac_consolidated_control AS f WHERE NOT EXISTS (SELECT 1 FROM dw.tac_control_line AS d WHERE d.control_line_key = f.control_line_key))
UNION ALL
SELECT N'TAC Consolidated Accounts to Fiscal Year', (SELECT COUNT_BIG(*) FROM dw.tac_consolidated_control),
       (SELECT COUNT_BIG(*) FROM dw.tac_consolidated_control AS f WHERE NOT EXISTS (SELECT 1 FROM dw.dim_period AS d WHERE d.financial_year = f.release))
UNION ALL
SELECT N'TAC Control Member to TAC Control Line', (SELECT COUNT_BIG(*) FROM dw.tac_control_member),
       (SELECT COUNT_BIG(*) FROM dw.tac_control_member AS f WHERE NOT EXISTS (SELECT 1 FROM dw.tac_control_line AS d WHERE d.control_line_key = f.control_line_key))
ORDER BY relationship;
