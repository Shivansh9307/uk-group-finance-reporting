-- requires: dw.tac_fact
-- Independent of the model: the section rows of audit.tac_cash_flow_section_residual (the net change row is test 161).
-- The reserve movements have no published side, so published is blank.
SELECT s.release AS [Financial Year], s.section AS [Cash Flow Section],
       CAST(s.derived_total AS decimal(38, 4)) AS derived,
       CAST(CASE WHEN s.section = N'Reserve movements (not cash)' THEN NULL ELSE s.published_total END AS decimal(38, 4)) AS published,
       CAST(s.residual AS decimal(38, 4)) AS residual
FROM audit.tac_cash_flow_section_residual AS s
WHERE s.section <> N'Net change in cash'
ORDER BY s.release, s.section;
