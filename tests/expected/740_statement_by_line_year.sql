-- Independent of the model: dw.v_statement_pnl computes every line in SQL from dw.fact_outturn and dw.fact_plan, through
-- dw.account_statement_line and dw.statement_line_member. One row per line and year that has an amount or a plan.
SELECT line_id AS [Line Id], financial_year AS [Financial Year],
       CAST(outturn AS decimal(38, 4)) AS outturn, CAST(plan_amount AS decimal(38, 4)) AS [plan],
       CAST(outturn_plan_basis AS decimal(38, 4)) AS outturn_plan_basis
FROM dw.v_statement_pnl
ORDER BY line_id, financial_year;
