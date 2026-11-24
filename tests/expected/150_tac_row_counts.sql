-- requires: dw.tac_fact
-- Independent of the model views: counts of the dw base tables, with the one documented extra member (Not compared) in the
-- derived cash-flow lines.
SELECT N'Fact TAC' AS table_name, COUNT_BIG(*) AS row_count FROM dw.tac_fact
UNION ALL
SELECT N'Fact TAC Cash Flow (derived)', COUNT_BIG(*) FROM dw.tac_cash_flow_derived
UNION ALL
SELECT N'TAC Provider', COUNT_BIG(*) FROM dw.tac_provider
UNION ALL
SELECT N'TAC Statement Line', COUNT_BIG(*) FROM dw.tac_statutory_line
UNION ALL
SELECT N'TAC Cash Flow Line', COUNT_BIG(*) + 1 FROM dw.tac_cash_flow_line
UNION ALL
SELECT N'TAC Control Line', COUNT_BIG(*) FROM dw.tac_control_line
UNION ALL
SELECT N'TAC Control Member', COUNT_BIG(*) FROM dw.tac_control_member
UNION ALL
SELECT N'TAC Consolidated Accounts', COUNT_BIG(*) FROM dw.tac_consolidated_control
ORDER BY table_name;
